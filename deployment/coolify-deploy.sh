#!/bin/bash
# Coolify deployment script with authentication handling
set -e

echo "=== Starting Coolify Deployment ==="

# Use the same Docker config location as build
export DOCKER_CONFIG=/tmp/docker-coolify

# Ensure we're still logged in (in case of container restart)
if [ ! -f "$DOCKER_CONFIG/config.json" ]; then
    echo "Re-authenticating with Docker registry..."
    mkdir -p $DOCKER_CONFIG
    echo '9sFPGGDJUFnE4z*z4Aj9' | docker login docker.reactmotion.com -u coolify-system --password-stdin
fi

# Run docker-compose with the correct config
echo "Starting services with docker-compose..."
DOCKER_CONFIG=$DOCKER_CONFIG docker-compose pull
DOCKER_CONFIG=$DOCKER_CONFIG docker-compose up -d

echo "=== Deployment complete ==="