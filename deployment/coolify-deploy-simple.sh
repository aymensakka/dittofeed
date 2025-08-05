#!/bin/bash
# Simplified deployment script for Coolify
set -e

echo "=== Coolify Deployment Script ==="

# Login to Docker registry with temporary config
echo "Logging into Docker registry..."
export DOCKER_CONFIG=/tmp/docker-temp-$(date +%s)
mkdir -p $DOCKER_CONFIG
echo '9sFPGGDJUFnE4z*z4Aj9' | docker login docker.reactmotion.com -u coolify-system --password-stdin

# Pull images (using the same temp config)
echo "Pulling images..."
DOCKER_CONFIG=$DOCKER_CONFIG docker pull docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1
DOCKER_CONFIG=$DOCKER_CONFIG docker pull docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1
DOCKER_CONFIG=$DOCKER_CONFIG docker pull docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1

# Create network if it doesn't exist
NETWORK_NAME="p0gcsc088cogco0cokco4404"
echo "Creating network: $NETWORK_NAME"
docker network create $NETWORK_NAME 2>/dev/null || echo "Network $NETWORK_NAME already exists or created"

# Start services
echo "Starting services..."
# Try docker compose first, fall back to docker-compose if not available
if command -v docker-compose &> /dev/null; then
    docker-compose -f docker-compose.coolify.yaml up -d
else
    docker compose -f docker-compose.coolify.yaml up -d
fi

echo "=== Deployment Complete ==="