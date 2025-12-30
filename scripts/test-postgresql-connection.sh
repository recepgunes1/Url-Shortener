#!/bin/bash

set -e

NODE_IP="${1:-localhost}"
PG_PORT="${2:-30432}"
PG_USER="${3:-postgres}"
PG_PASSWORD="${4:-password}"
PG_DATABASE="${5:-postgres}"

echo "Testing PostgreSQL..."

PGPASSWORD="$PG_PASSWORD" psql \
    -h "$NODE_IP" \
    -p "$PG_PORT" \
    -U "$PG_USER" \
    -d "$PG_DATABASE" \
    -c "SELECT 1;" &>/dev/null

if [ $? -eq 0 ]; then
    echo "PostgreSQL connection successful"
    exit 0
else
    echo "PostgreSQL connection failed"
    exit 1
fi
