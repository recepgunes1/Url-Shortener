#!/bin/bash

# Exit immediately if any command fails
set -e

# Namespace is required - show usage if not provided
NAMESPACE="${1:?Usage: $0 <namespace> [host] [port]}"

# External host and port are optional. If not provided, internal Kubernetes DNS will be used
EXTERNAL_HOST="${2:-}"
EXTERNAL_PORT="${3:-}"

echo "Testing PostgreSQL..."

# Retrieve the PostgreSQL connection string from Kubernetes secret, then base64 decodes it
PG_CONN=$(kubectl get secret url-shortener-secrets -n "$NAMESPACE" -o jsonpath='{.data.ConnectionStrings__Database}' | base64 -d)

# Determine host and port based on whether external parameters were provided
if [ -n "$EXTERNAL_HOST" ] && [ -n "$EXTERNAL_PORT" ]; then
    # Use external connection (NodePort access from outside cluster)
    HOST="$EXTERNAL_HOST"
    PORT="$EXTERNAL_PORT"
else
    # Parse host and port from connection string (internal Kubernetes DNS)
    HOST=$(echo "$PG_CONN" | grep -oP 'Host=\K[^;]+')
    PORT=$(echo "$PG_CONN" | grep -oP 'Port=\K[^;]+')
fi

# Parse database name, username, and password from connection string
DB=$(echo "$PG_CONN" | grep -oP 'Database=\K[^;]+')
USER=$(echo "$PG_CONN" | grep -oP 'Username=\K[^;]+')
PASS=$(echo "$PG_CONN" | grep -oP 'Password=\K[^;]+')

# Attempt to connect to PostgreSQL and execute a simple query
if psql "postgresql://${USER}:${PASS}@${HOST}:${PORT}/${DB}" -c "SELECT 1;" &>/dev/null; then
    echo "PostgreSQL connection successful"
else
    echo "PostgreSQL connection failed"
    exit 1
fi
