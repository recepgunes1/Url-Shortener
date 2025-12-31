# URL Shortener

A URL shortening service deployed on a local k3s Kubernetes cluster with PostgreSQL and Redis.

## Architecture
If the diagrams are hard to read, refer to [MERMAIDS.md](/MERMAIDS.md) for zooming and other interactive features.

### Overview
![Overview](/diagrams/overview.svg)

### Cluster
![Cluster](/diagrams/cluster.svg)

### CI/CD Workflow
![CI/CD](/diagrams/cicd.svg)

### pre-commit Workflow
![pre-commit](/diagrams/pre-commit.svg)

## Project Structure

```
.
├── .github/workflows/        # CI/CD pipelines
├── charts/url-shortener/     # Helm chart for the application
├── scripts/
│   ├── install-dependencies.sh
│   ├── deploy-stack.sh
│   ├── test-postgresql-connection.sh
│   └── test-redis-connection.sh
├── src/                      # .NET application source
├── test/                     # .NET application tests
└── utils/                    # Docker compose for local development
```

## Prerequisites

- Ubuntu VM (tested on Ubuntu 24.04)
- User with sudo privileges (not root)

## Quick Start

### 1. Install Dependencies

```bash
./scripts/install-dependencies.sh
```

This installs: k3s, Helm, kubectl, redis-tools, postgresql-client

### 2. Deploy the Stack

In staging, the API documentation is available at `/scalar` for testing endpoints.

```bash
./scripts/deploy-stack.sh up staging

./scripts/deploy-stack.sh up production
```

### 3. Tear Down

```bash
./scripts/deploy-stack.sh down staging

./scripts/deploy-stack.sh down production
```

## External Access

After deployment, services are accessible via NodePort:

| Service    | Staging Port | Production Port |
|------------|--------------|-----------------|
| API        | 30080        | 30081           |
| PostgreSQL | 30432        | 30433           |
| Redis      | 30380        | 30381           |

## Testing Connectivity

PostgreSQL and Redis connectivity tests run automatically after `deploy-stack.sh up` completes.

To test manually later:

```bash
./scripts/test-postgresql-connection.sh <namespace> <host> <port>

./scripts/test-redis-connection.sh <namespace> <host> <port>
```

## Development

### Requirements

- Docker and Docker Compose installed
- .NET 10 (only if you want to code without Docker)

### Setup

#### 1. Running Services 

Copy and edit the example env file:

```bash
cp ./utils/.env.example .env
```

Start services:

```bash
docker compose --env-file .env -f utils/docker-compose.development.yaml up -d
```

##### (Optional) 1.1 Build an image and run container 
```
docker build -t url-shortener:latest -f src/UrlShortener.API/Dockerfile .
docker run -p 8080:8080 -p 8001:8001 \
  -e ConnectionStrings__Database="your_db_connection" \
  -e ConnectionStrings__Redis="your_redis_connection" \
  -e Url__CacheExpiresInDays="1" \
  -e Url__CodeLength="6" \
  -d url-shortener:latest
```

#### 2. Monitor Locally

Needed for local monitoring:

```bash
docker run -p 18888:18888 -p 4317:4317 -d mcr.microsoft.com/dotnet/aspire-dashboard:latest
```

Find the url from container logs

---
