#!/bin/bash
# Coolify pre-deployment: Login and pull images
set -e

echo "=== Pre-deployment: Docker Login and Pull ==="

# Use a persistent config location
export DOCKER_CONFIG=/tmp/docker-coolify
mkdir -p $DOCKER_CONFIG

# Login to Docker registry
echo "Logging into Docker registry..."
echo '9sFPGGDJUFnE4z*z4Aj9' | docker login docker.reactmotion.com -u coolify-system --password-stdin

# Pull all images
echo "Pulling images from registry..."
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1
docker pull postgres:15-alpine
docker pull redis:7-alpine

echo "=== All images pulled successfully ==="