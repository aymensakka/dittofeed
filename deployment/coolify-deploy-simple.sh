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
# Check which command is available
if docker compose version &> /dev/null; then
    echo "Using 'docker compose' command..."
    docker compose -f docker-compose.coolify.yaml up -d
elif docker-compose --version &> /dev/null; then
    echo "Using 'docker-compose' command..."
    docker-compose -f docker-compose.coolify.yaml up -d
else
    echo "Neither 'docker compose' nor 'docker-compose' found!"
    echo "Attempting direct docker run commands..."
    # Start services individually
    cd /artifacts/*/
    docker run -d --name postgres-p0gcsc088cogco0cokco4404 \
        --network p0gcsc088cogco0cokco4404 \
        -e POSTGRES_DB=dittofeed \
        -e POSTGRES_USER=dittofeed \
        -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
        -v postgres_data:/var/lib/postgresql/data \
        postgres:15-alpine
    
    docker run -d --name redis-p0gcsc088cogco0cokco4404 \
        --network p0gcsc088cogco0cokco4404 \
        -e REDIS_PASSWORD="${REDIS_PASSWORD}" \
        -v redis_data:/data \
        redis:7-alpine
    
    # Wait for dependencies
    sleep 10
    
    # Start other services...
    echo "Services started individually"
fi

echo "=== Deployment Complete ==="