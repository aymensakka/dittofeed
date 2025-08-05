#!/bin/bash
# Deployment script that ensures docker-compose is available
set -e

echo "=== Coolify Deployment with Docker Compose ==="

# Login to Docker registry
echo "Logging into Docker registry..."
export DOCKER_CONFIG=/tmp/docker-temp-$(date +%s)
mkdir -p $DOCKER_CONFIG
echo '9sFPGGDJUFnE4z*z4Aj9' | docker login docker.reactmotion.com -u coolify-system --password-stdin

# Pull images
echo "Pulling images..."
DOCKER_CONFIG=$DOCKER_CONFIG docker pull docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1
DOCKER_CONFIG=$DOCKER_CONFIG docker pull docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1
DOCKER_CONFIG=$DOCKER_CONFIG docker pull docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1

# Create network
NETWORK_NAME="p0gcsc088cogco0cokco4404"
echo "Creating network: $NETWORK_NAME"
docker network create $NETWORK_NAME 2>/dev/null || echo "Network already exists"

# Install docker-compose if not available
if ! command -v docker-compose &> /dev/null; then
    echo "Installing docker-compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Start services
echo "Starting services with docker-compose..."
cd /artifacts/*/
/usr/local/bin/docker-compose -f docker-compose.coolify.yaml up -d

echo "=== Deployment Complete ==="