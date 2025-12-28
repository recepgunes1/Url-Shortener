#UrlShortener

install pre-commit hooks for contrubiting project.

use for dependencies
```
docker compose --env-file .env -f utils/docker-compose.development.yaml up -d
```

monitoring is needed during development
```
docker run --rm -it -p 18888:18888 -p 4317:18889 -d mcr.microsoft.com/dotnet/aspire-dashboard:latest
```
