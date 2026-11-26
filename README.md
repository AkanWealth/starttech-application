# starttech-application

React frontend and Go backend for StartTech, with Kubernetes manifests and GitHub Actions pipelines.

```
Browser --HTTPS--> CloudFront --+-- *      --> S3-Frontend (React build)
                                +-- /api/* --> ALB-Backend --> NodePort 30080 --> backend-api pod :8080
```

The frontend calls the API with relative paths (`/api/v1/...`), so both are served from the same CloudFront domain.

## Layout

```
.github/workflows/frontend-ci-cd.yml   npm ci -> npm audit -> npm run build -> aws s3 sync -> CloudFront invalidation
.github/workflows/backend-ci-cd.yml    go test -> docker build -> Trivy scan -> ECR push -> kubectl apply -> rollout status
frontend/                              React source
backend/                               Go source and Dockerfile
k8s/                                   deployment.yaml, service.yaml, ingress.yaml
scripts/                               deploy-frontend.sh, deploy-backend.sh, health-check.sh, rollback.sh
```

## Backend

- Health check: `/health` and `/api/v1/health`
- Environment variables: `REDIS_HOST` (ElastiCache endpoint), `MONGO_URI` (Atlas connection string), `JWT_SECRET_KEY`
- Logs: JSON to stdout

## GitHub configuration

| Kind     | Name                         | Value                                     |
| -------- | ---------------------------- | ----------------------------------------- |
| Secret   | `AWS_ACCESS_KEY_ID`          | Access key of the deploying IAM user      |
| Secret   | `AWS_SECRET_ACCESS_KEY`      | Secret key of the deploying IAM user      |
| Secret   | `MONGO_URI`                  | MongoDB Atlas connection string           |
| Secret   | `JWT_SECRET_KEY`             | Random string for signing JWTs            |
| Variable | `AWS_REGION`                 | e.g. `us-east-1`                          |
| Variable | `S3_BUCKET`                  | Terraform output `s3_bucket_name`         |
| Variable | `CLOUDFRONT_DISTRIBUTION_ID` | Terraform output `cloudfront_distribution_id` |
| Variable | `REDIS_HOST`                 | Terraform output `redis_endpoint`         |

Use the same IAM user that ran the first `terraform apply`: EKS grants the cluster creator admin access, which `kubectl` needs.
