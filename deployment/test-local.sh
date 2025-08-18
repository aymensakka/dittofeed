#!/bin/bash

# ==============================================================================
# Test Complete Stack Locally
# ==============================================================================

set -e

# Export consistent environment variables
export POSTGRES_PASSWORD="testpassword123"
export REDIS_PASSWORD="testpassword123"
export CLICKHOUSE_PASSWORD="testpassword123"
export CLICKHOUSE_USER="dittofeed"
export JWT_SECRET="test-jwt-secret-32-chars-minimum"
export SECRET_KEY="test-secret-key-32-chars-minimum"
export NEXTAUTH_SECRET="test-nextauth-secret"
export AUTH_MODE="multi-tenant"
export CF_TUNNEL_TOKEN="dummy-token"

echo "Starting complete stack with test configuration..."

# Start infrastructure services first
echo "Starting PostgreSQL and Redis..."
docker compose -f docker-compose.coolify.yaml up -d postgres redis

# Wait for them to be healthy
sleep 10

echo "Starting ClickHouse..."
docker compose -f docker-compose.coolify.yaml up -d clickhouse

sleep 10

echo "Starting Temporal..."
docker compose -f docker-compose.coolify.yaml up -d temporal

sleep 15

echo "Checking services status..."
docker ps --format "table {{.Names}}\t{{.Status}}"

echo "Done. Check the services with: docker ps"