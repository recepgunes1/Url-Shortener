#!/bin/bash

set -e

PG_URL="${1:-postgresql://postgres:password@localhost:5432/postgres}"

echo "Testing PostgreSQL..."

psql "$PG_URL" -c "SELECT 1;" &>/dev/null

if [ $? -eq 0 ]; then
    echo "PostgreSQL connection successful"
    exit 0
else
    echo "PostgreSQL connection failed"
    exit 1
fi
