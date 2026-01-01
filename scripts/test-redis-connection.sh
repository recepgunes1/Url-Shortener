#!/bin/bash

# Exit immediately if any command fails
set -e

# Namespace is required - show usage if not provided
NAMESPACE="${1:?Usage: $0 <namespace> [host] [port]}"

# External host and port are optional. If not provided, internal Kubernetes DNS will be used
EXTERNAL_HOST="${2:-}"
EXTERNAL_PORT="${3:-}"

echo "Testing Redis..."

# Retrieve the PostgreSQL connection string from Kubernetes secret, then base64 decodes it
REDIS_CONN=$(kubectl get secret url-shortener-secrets -n "$NAMESPACE" -o jsonpath='{.data.ConnectionStrings__Redis}' | base64 -d)

# Determine host and port based on whether external parameters were provided
if [ -n "$EXTERNAL_HOST" ] && [ -n "$EXTERNAL_PORT" ]; then
    # Use external connection (NodePort access from outside cluster)
    HOST="$EXTERNAL_HOST"
    PORT="$EXTERNAL_PORT"
else
    # Parse host and port from connection string (internal Kubernetes DNS)
    HOST=$(echo "$REDIS_CONN" | cut -d: -f1)
    PORT=$(echo "$REDIS_CONN" | cut -d: -f2 | cut -d, -f1)
fi

# Parse username and password from connection string
USER=$(echo "$REDIS_CONN" | grep -oP 'user=\K[^,]+')
PASS=$(echo "$REDIS_CONN" | grep -oP 'password=\K[^,]+')

# Attempt to connect to Redis and send PING command
if redis-cli -h "$HOST" -p "$PORT" --user "$USER" --pass "$PASS" PING &>/dev/null; then
    echo "Redis connection successful"
else
    echo "Redis connection failed"
    exit 1
fi
