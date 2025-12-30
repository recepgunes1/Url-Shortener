#!/bin/bash

set -e

NODE_IP="${1:-localhost}"
REDIS_PORT="${2:-30380}"
REDIS_USER="${3:-default}"
REDIS_PASSWORD="${4:-password}"

echo "Testing Redis..."

redis-cli \
    -h "$NODE_IP" \
    -p "$REDIS_PORT" \
    -u "redis://${REDIS_USER}:${REDIS_PASSWORD}@${NODE_IP}:${REDIS_PORT}" \
    PING &>/dev/null

if [ $? -eq 0 ]; then
    echo "Redis connection successful"
    exit 0
else
    echo "Redis connection failed"
    exit 1
fi
