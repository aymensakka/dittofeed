#!/bin/bash
# Simplified deployment script for Coolify
set -e

echo "=== Coolify Deployment Script ==="

# Login to Docker registry
echo "Logging into Docker registry..."
echo '9sFPGGDJUFnE4z*z4Aj9' | docker login docker.reactmotion.com -u coolify-system --password-stdin

# Pull images
echo "Pulling images..."
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1

# Create network if it doesn't exist
NETWORK_NAME="p0gcsc088cogco0cokco4404"
echo "Creating network: $NETWORK_NAME"
docker network create $NETWORK_NAME 2>/dev/null || echo "Network $NETWORK_NAME already exists or created"

# Start services
echo "Starting services..."
docker compose -f docker-compose.coolify.yaml up -d

echo "=== Deployment Complete ==="