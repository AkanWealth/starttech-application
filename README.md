# starttech-application

Source code, Kubernetes manifests and delivery pipelines for the StartTech "MuchToDo" app:

- **frontend/**: React 19 + Vite + TanStack Router. Built to static files, hosted on S3, served by CloudFront.
- **backend/**: Go (Gin) REST API on Amazon EKS. Uses MongoDB Atlas for storage and ElastiCache Redis for caching.

The AWS infrastructure is provisioned by [starttech-infra](../starttech-infra).

## Repository layout

```
starttech-application/
├── .github/workflows/
│   ├── frontend-ci-cd.yml     # npm ci -> npm audit -> build -> s3 sync -> CloudFront invalidation
│   └── backend-ci-cd.yml      # go test -> docker build -> Trivy -> ECR push -> kubectl apply -> rollout check
├── frontend/                  # React source (package.json, src/)
├── backend/                   # Go source (main.go, Dockerfile, internal/)
├── k8s/
│   ├── deployment.yaml        # namespace, backend-api Deployment, PodDisruptionBudget
│   ├── service.yaml           # NodePort 30080 -> container port 8080
│   └── ingress.yaml           # alb ingress class, /api routing
└── scripts/
    ├── deploy-frontend.sh
    ├── deploy-backend.sh
    ├── health-check.sh
    ├── rollback.sh
    └── common.sh              # shared helpers for the scripts
```

## How requests flow

```
Browser ── https://<id>.cloudfront.net/todos        ──> CloudFront ──> S3-Frontend  (index.html, assets)
        └─ https://<id>.cloudfront.net/api/v1/tasks ──> CloudFront ──> ALB-Backend ──> NodePort 30080 ──> backend-api pod :8080
```

The frontend uses **relative API paths**. The Axios base URL is `/api/v1` ([frontend/src/lib/apiClient.ts](frontend/src/lib/apiClient.ts)), so every call goes to the same HTTPS CloudFront domain. That avoids mixed-content blocking and CORS. In local development, Vite proxies `/api` to `localhost:8080` the same way.

## Backend

| Item | Value |
|---|---|
| Container port | `8080` |
| Health check | `GET /api/v1/health` (also `/health`): checks MongoDB and Redis, returns 200 or 503 |
| Liveness | `GET /api/v1/ping` (also `/ping`): no dependency checks |
| Logs | JSON on stdout, one line per request (`request_id`, `method`, `path`, `status`, `latency`), ready for Container Insights or Fluent Bit |
| Image | Multi-stage build to `distroless/static:nonroot`, tagged with the git SHA |

Every route is served both at the root and under `/api/v1`, because CloudFront forwards the `/api/...` path unchanged.

### Environment variables

| Variable | Source in EKS | Description |
|---|---|---|
| `MONGO_URI` | Secret `backend-secrets` | MongoDB Atlas connection string |
| `JWT_SECRET_KEY` | Secret `backend-secrets` | Signing key for session tokens |
| `REDIS_HOST` | ConfigMap `backend-config` | ElastiCache endpoint (`host` or `host:port`) |
| `REDIS_PORT` | default `6379` | Used when `REDIS_HOST` has no port |
| `ENABLE_CACHE` | `true` in the manifest | Turns on Redis caching |
| `COOKIE_DOMAINS`, `ALLOWED_ORIGINS` | ConfigMap `backend-config` | Set to the CloudFront domain |
| `PORT`, `DB_NAME`, `LOG_FORMAT`, `LOG_LEVEL`, `SECURE_COOKIE` | manifest | `8080`, `much_todo_db`, `json`, `INFO`, `true` |

The pipeline creates the Secret and ConfigMap at deploy time from GitHub secrets and AWS lookups. No credentials are committed.

## Kubernetes

- Namespace `starttech`, Deployment `backend-api` with 2 replicas.
- Rolling update with `maxSurge: 1` and `maxUnavailable: 0`, so capacity never drops during a rollout.
- Startup, readiness (`/api/v1/health`) and liveness (`/ping`) probes, plus CPU and memory requests and limits.
- Pods run as non-root with a read-only root filesystem and all capabilities dropped. They are spread across nodes, and a PodDisruptionBudget keeps at least one pod up.
- The `backend-api` Service is a NodePort (`80 -> 8080`, nodePort `30080`). The Terraform-managed ALB sends traffic to that port on every node.
- `ingress.yaml` defines the same routing with `ingressClassName: alb` for the AWS Load Balancer Controller. See the design notes in the infra README for why the ALB is owned by Terraform.

## CI/CD

Both workflows sign in to AWS with **GitHub OIDC** (`aws-actions/configure-aws-credentials`). GitHub stores no AWS access keys. Pull requests run the build, test and scan steps but never deploy.

### Frontend: `frontend-ci-cd.yml` (changes under `frontend/`)
1. `npm ci`
2. `npm audit --audit-level=high` (security gate)
3. `npm run lint` and `npm run build`
4. `aws s3 sync` to the frontend bucket. Hashed assets get a one-year cache; `index.html` is set to `no-cache`.
5. `aws cloudfront create-invalidation --distribution-id <id> --paths "/*"`

### Backend: `backend-ci-cd.yml` (changes under `backend/` or `k8s/`)
1. `go vet` and `go test ./...`
2. `docker build`, tagged with `${{ github.sha }}`
3. Trivy image scan. The pipeline fails on fixable HIGH or CRITICAL findings, and ECR also scans on push.
4. Log in to Amazon ECR and push `starttech-backend-api:<sha>`
5. Write the new image tag into `k8s/deployment.yaml`
6. `aws eks update-kubeconfig`, create the ConfigMap and Secret, then `kubectl apply -f k8s/`
7. `kubectl rollout status deployment/backend-api`, then [scripts/health-check.sh](scripts/health-check.sh) (in-cluster and through CloudFront)
8. If the rollout or health check fails, [scripts/rollback.sh](scripts/rollback.sh) runs `kubectl rollout undo`

### GitHub settings

Create a GitHub environment named `production`, then add:

| Type | Name | Value |
|---|---|---|
| Secret | `AWS_ROLE_ARN` | `github_app_role_arn` output from starttech-infra |
| Secret | `MONGO_URI` | MongoDB Atlas connection string |
| Secret | `JWT_SECRET_KEY` | long random string, e.g. `openssl rand -hex 32` |
| Variable | `AWS_REGION` | same region as the infrastructure |
| Variable (optional) | `S3_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID`, `CLOUDFRONT_DOMAIN`, `REDIS_HOST` | Terraform outputs. If unset, the workflows look them up by the StartTech naming conventions. |

Deploy order for a new environment: **infrastructure → backend → frontend**. Run them from the Actions tab with "Run workflow" or by pushing to `main`.

## Scripts

The scripts run the same steps by hand. Each reads the environment variables above and looks up anything unset in AWS.

```bash
# Frontend: install, audit, build, sync to S3, invalidate CloudFront
./scripts/deploy-frontend.sh

# Backend: test, build, scan (if trivy is installed), push, deploy, verify
MONGO_URI='mongodb+srv://...' JWT_SECRET_KEY='...' ./scripts/deploy-backend.sh

# Health: deployment status, in-cluster /api/v1/health, and https://<cloudfront>/api/v1/health
./scripts/health-check.sh

# Roll back to the previous revision, or to a specific one
./scripts/rollback.sh
./scripts/rollback.sh 3        # revisions: kubectl rollout history deployment/backend-api -n starttech
```

## Local development

```bash
# Backend (MongoDB and Redis in Docker)
cd backend
cp .env.example .env          # set JWT_SECRET_KEY and MONGO_URI
docker compose up -d
go run .                      # http://localhost:8080/api/v1/health

# Frontend (proxies /api to localhost:8080)
cd frontend
npm ci
npm run dev                   # http://localhost:5173
```

Tests:

```bash
cd backend && go test ./...                                         # unit tests
cd backend && INTEGRATION=true go test -tags=integration ./...      # needs Docker
```
