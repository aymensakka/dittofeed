#!/bin/bash
# Coolify build script with persistent Docker authentication
set -e

echo "=== Starting Coolify Build Process ==="

# Step 1: Setup persistent Docker config location
export DOCKER_CONFIG=/tmp/docker-coolify
mkdir -p $DOCKER_CONFIG

echo "Using Docker config at: $DOCKER_CONFIG"

# Step 2: Login to Docker registry
echo "Logging into Docker registry..."
echo '9sFPGGDJUFnE4z*z4Aj9' | docker login docker.reactmotion.com -u coolify-system --password-stdin

# Step 3: Verify login was successful
if docker pull docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1 2>&1 | head -1 | grep -q "Pulling"; then
    echo "✓ Docker authentication successful"
else
    echo "✗ Docker authentication failed, retrying..."
    # Retry with direct password
    docker login docker.reactmotion.com -u coolify-system -p '9sFPGGDJUFnE4z*z4Aj9'
fi

# Step 4: Pull all images explicitly before docker-compose
echo "Pre-pulling images..."
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1 &
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1 &
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1 &

# Wait for all pulls
wait

echo "=== Build process complete ==="