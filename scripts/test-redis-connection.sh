#!/bin/bash

set -e

NAMESPACE="${1:-}"
EXTERNAL_HOST="${2:-}"
EXTERNAL_PORT="${3:-}"

echo "Testing Redis..."

REDIS_CONN=$(kubectl get secret url-shortener-secrets -n "$NAMESPACE" -o jsonpath='{.data.ConnectionStrings__Redis}' | base64 -d)

if [ -n "$EXTERNAL_HOST" ] && [ -n "$EXTERNAL_PORT" ]; then
    HOST="$EXTERNAL_HOST"
    PORT="$EXTERNAL_PORT"
else
    HOST=$(echo "$REDIS_CONN" | cut -d: -f1)
    PORT=$(echo "$REDIS_CONN" | cut -d: -f2 | cut -d, -f1)
fi

USER=$(echo "$REDIS_CONN" | grep -oP 'user=\K[^,]+')
PASS=$(echo "$REDIS_CONN" | grep -oP 'password=\K[^,]+')

if redis-cli -h "$HOST" -p "$PORT" --user "$USER" --pass "$PASS" PING &>/dev/null; then
    echo "Redis connection successful"
else
    echo "Redis connection failed"
    exit 1
fi
