#!/bin/bash
# Complete deployment script for Coolify
set -e

echo "=== Starting Deployment ==="

# Source environment variables if .env.prod exists
if [ -f .env.prod ]; then
    echo "Loading environment variables from .env.prod..."
    # Filter out lines with inline comments and source safely
    set -a
    grep -v '^#' .env.prod | grep '=' | sed 's/#.*//' > /tmp/env.tmp
    source /tmp/env.tmp
    rm -f /tmp/env.tmp
    set +a
fi

# Step 1: Clean any locked Docker configs
echo "Cleaning Docker config..."
rm -rf /root/.docker/config.json* 2>/dev/null || true
rm -rf /tmp/docker-* 2>/dev/null || true

# Step 2: Login with temporary config
echo "Logging into Docker registry..."
DOCKER_CONFIG=/tmp/docker-deploy docker login docker.reactmotion.com -u coolify-system -p '9sFPGGDJUFnE4z*z4Aj9'

# Step 3: Pull all images BEFORE docker-compose
echo "Pulling all required images..."
DOCKER_CONFIG=/tmp/docker-deploy docker pull docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1
DOCKER_CONFIG=/tmp/docker-deploy docker pull docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1  
DOCKER_CONFIG=/tmp/docker-deploy docker pull docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1
docker pull postgres:15-alpine
docker pull redis:7-alpine

# Step 4: Now run docker compose with Coolify-specific config (no custom network)
echo "Starting services..."
docker compose -f docker-compose.coolify.yaml up -d

echo "=== Deployment Complete ==="