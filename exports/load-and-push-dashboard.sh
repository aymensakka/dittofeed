#!/bin/bash

# Script to load and push dashboard image from a server with better connectivity
# Usage: Run this script on the server after transferring dashboard.tar.gz

echo "=== Dashboard Image Load and Push Script ==="
echo

# Check if dashboard.tar.gz exists
if [ ! -f "dashboard.tar.gz" ]; then
    echo "❌ Error: dashboard.tar.gz not found in current directory"
    echo "Please ensure you've transferred the file to this server"
    exit 1
fi

# Registry details
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo"
USERNAME="coolify-system"
PASSWORD='9sFPGGDJUFnE4z*z4Aj9'

echo "Loading dashboard image from archive..."
docker load < dashboard.tar.gz

if [ $? -ne 0 ]; then
    echo "❌ Failed to load image"
    exit 1
fi

echo "✅ Image loaded successfully"
echo

# Login to registry
echo "Logging in to Nexus registry..."
echo "$PASSWORD" | docker login "$REGISTRY" -u "$USERNAME" --password-stdin

if [ $? -ne 0 ]; then
    echo "❌ Login failed"
    exit 1
fi

echo "✅ Login successful"
echo

# Push the image
IMAGE="docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1"
echo "Pushing $IMAGE..."
docker push "$IMAGE"

if [ $? -eq 0 ]; then
    echo "✅ Successfully pushed dashboard:multitenancy-redis-v1"
    
    # Also push latest tag
    echo
    echo "Creating and pushing latest tag..."
    docker tag "$IMAGE" "$REGISTRY/$REPO/dittofeed/dashboard:latest"
    docker push "$REGISTRY/$REPO/dittofeed/dashboard:latest"
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully pushed dashboard:latest"
    else
        echo "❌ Failed to push dashboard:latest"
    fi
else
    echo "❌ Failed to push dashboard image"
    echo "Please ensure you have a stable internet connection"
fi

echo
echo "=== Process Complete ==="