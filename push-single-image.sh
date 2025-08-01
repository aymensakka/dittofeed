#!/bin/bash

# Single image push script for slow connections
# Usage: ./push-single-image.sh <service-name>
# Example: ./push-single-image.sh worker

if [ -z "$1" ]; then
    echo "Usage: $0 <service-name>"
    echo "Example: $0 worker"
    echo "Available services: api, worker, dashboard"
    exit 1
fi

SERVICE=$1
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo"
USERNAME="coolify-system"
PASSWORD='9sFPGGDJUFnE4z*z4Aj9'

echo "=== Pushing $SERVICE image to Nexus ==="
echo

# Login to registry
echo "Logging in to Nexus registry..."
echo "$PASSWORD" | docker login "$REGISTRY" -u "$USERNAME" --password-stdin

if [ $? -ne 0 ]; then
    echo "❌ Login failed"
    exit 1
fi

echo "✓ Login successful"
echo

# Image details
IMAGE="dittofeed/$SERVICE:multitenancy-redis-v1"
FULL_IMAGE="$REGISTRY/$REPO/$IMAGE"

# Get image size
SIZE=$(docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep "$FULL_IMAGE" | awk '{print $2}')

echo "📦 Pushing $FULL_IMAGE"
echo "   Size: $SIZE"
echo "   Note: This may take 5-10 minutes on a 50 Mb/s connection"
echo

# Show start time
START_TIME=$(date +%s)
echo "Start time: $(date)"
echo

# Push the image
docker push "$FULL_IMAGE"
RESULT=$?

# Show end time and duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo
echo "End time: $(date)"
echo "Duration: ${DURATION} seconds"

if [ $RESULT -eq 0 ]; then
    echo "✅ Successfully pushed $SERVICE image"
    
    # Also push latest tag
    echo
    echo "Now pushing latest tag..."
    docker tag "$FULL_IMAGE" "$REGISTRY/$REPO/dittofeed/$SERVICE:latest"
    docker push "$REGISTRY/$REPO/dittofeed/$SERVICE:latest"
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully pushed $SERVICE:latest"
    else
        echo "❌ Failed to push $SERVICE:latest"
    fi
else
    echo "❌ Failed to push $SERVICE image"
    echo
    echo "If this failed due to network issues, you can run this script again."
    echo "Docker will resume from where it left off."
fi