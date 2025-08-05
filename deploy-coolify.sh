#!/bin/bash
# Root level deployment script for Coolify
set -e

echo "=== Dittofeed Coolify Deployment ==="
echo "Current directory: $(pwd)"
echo "Contents: $(ls -la)"

# Login to Docker registry
echo "Logging into Docker registry..."
export DOCKER_CONFIG=/tmp/docker-temp-$(date +%s)
mkdir -p $DOCKER_CONFIG
echo '9sFPGGDJUFnE4z*z4Aj9' | docker login docker.reactmotion.com -u coolify-system --password-stdin

# Pull images
echo "Pulling images..."
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1

# Create network
NETWORK_NAME="p0gcsc088cogco0cokco4404"
echo "Creating network: $NETWORK_NAME"
docker network create $NETWORK_NAME 2>/dev/null || true

# Try to use docker compose/docker-compose
echo "Starting services..."
if command -v docker-compose &> /dev/null; then
    docker-compose -f docker-compose.coolify.yaml up -d
elif docker compose version &> /dev/null; then
    docker compose -f docker-compose.coolify.yaml up -d
else
    echo "ERROR: Neither docker-compose nor docker compose found"
    # Try installing docker-compose
    echo "Attempting to install docker-compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-linux-x86_64" -o /tmp/docker-compose
    chmod +x /tmp/docker-compose
    /tmp/docker-compose -f docker-compose.coolify.yaml up -d
fi

echo "=== Deployment Complete ==="