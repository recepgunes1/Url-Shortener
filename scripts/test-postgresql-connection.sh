#!/bin/bash

set -e

NAMESPACE="${1:?Usage: $0 <namespace> [host] [port]}"
EXTERNAL_HOST="${2:-}"
EXTERNAL_PORT="${3:-}"

echo "Testing PostgreSQL..."

PG_CONN=$(kubectl get secret url-shortener-secrets -n "$NAMESPACE" -o jsonpath='{.data.ConnectionStrings__Database}' | base64 -d)

if [ -n "$EXTERNAL_HOST" ] && [ -n "$EXTERNAL_PORT" ]; then
    HOST="$EXTERNAL_HOST"
    PORT="$EXTERNAL_PORT"
else
    HOST=$(echo "$PG_CONN" | grep -oP 'Host=\K[^;]+')
    PORT=$(echo "$PG_CONN" | grep -oP 'Port=\K[^;]+')
fi

DB=$(echo "$PG_CONN" | grep -oP 'Database=\K[^;]+')
USER=$(echo "$PG_CONN" | grep -oP 'Username=\K[^;]+')
PASS=$(echo "$PG_CONN" | grep -oP 'Password=\K[^;]+')

if psql "postgresql://${USER}:${PASS}@${HOST}:${PORT}/${DB}" -c "SELECT 1;" &>/dev/null; then
    echo "PostgreSQL connection successful"
else
    echo "PostgreSQL connection failed"
    exit 1
fi
