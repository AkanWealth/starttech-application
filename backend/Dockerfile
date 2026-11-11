# syntax=docker/dockerfile:1

# ---- Build stage ----
# Tracks the latest 1.26.x patch (go.mod requires >= 1.26.10).
FROM golang:1.26-alpine AS build
WORKDIR /src

# Cache module downloads separately from the source code.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath \
    -ldflags="-s -w -X main.version=${VERSION}" \
    -o /out/backend-api .

# ---- Runtime stage ----
# Distroless static image: no shell or package manager, runs as non-root.
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/backend-api /app/backend-api

ENV PORT=8080 \
    LOG_FORMAT=json \
    LOG_LEVEL=INFO \
    GIN_MODE=release

EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/backend-api"]
