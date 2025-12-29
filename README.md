# Url-Shortener
A URL shortening service built with .NET.

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
