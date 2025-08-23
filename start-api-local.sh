#!/bin/bash

# Load environment variables from .env file
export $(cat .env | grep -v '^#' | xargs)

cd packages/api

# Start API with environment variables
AUTH_MODE=${AUTH_MODE:-multi-tenant} \
AUTH_PROVIDER=${AUTH_PROVIDER:-google} \
DATABASE_URL=${DATABASE_URL:-postgresql://dittofeed:password@localhost:5433/dittofeed} \
REDIS_HOST=${REDIS_HOST:-localhost} \
REDIS_PORT=${REDIS_PORT:-6380} \
CLICKHOUSE_HOST=${CLICKHOUSE_HOST:-localhost} \
CLICKHOUSE_PORT=${CLICKHOUSE_PORT:-8124} \
CLICKHOUSE_USER=${CLICKHOUSE_USER:-dittofeed} \
CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD:-password} \
TEMPORAL_ADDRESS=${TEMPORAL_ADDRESS:-localhost:7234} \
JWT_SECRET=${JWT_SECRET:-your-jwt-secret} \
SECRET_KEY=${SECRET_KEY:-your-secret-key-for-sessions-change-in-production} \
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID} \
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET} \
yarn dev
