#!/bin/bash

echo "=== Nexus Docker Registry Push Script ==="
echo

# Registry details
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo"
USERNAME="coolify-system"
PASSWORD='9sFPGGDJUFnE4z*z4Aj9'

# Since we're using HTTPS, no need to check for insecure registry
echo "Using HTTPS registry at $REGISTRY"

# Login to registry
echo
echo "Logging in to Nexus registry..."
echo "$PASSWORD" | docker login "$REGISTRY" -u "$USERNAME" --password-stdin

if [ $? -ne 0 ]; then
    echo "❌ Login failed. Please check your credentials and Docker configuration."
    exit 1
fi

echo "✓ Login successful"

# Images to push
IMAGES=(
    "dittofeed/api:multitenancy-redis-v1"
    "dittofeed/worker:multitenancy-redis-v1"
    "dittofeed/dashboard:multitenancy-redis-v1"
    "dittofeed/api:latest"
    "dittofeed/worker:latest"
    "dittofeed/dashboard:latest"
)

# Push images
echo
echo "Pushing images to Nexus..."
for IMAGE in "${IMAGES[@]}"; do
    FULL_IMAGE="$REGISTRY/$REPO/$IMAGE"
    echo
    echo "📦 Pushing $FULL_IMAGE..."
    docker push "$FULL_IMAGE"
    
    if [ $? -eq 0 ]; then
        echo "✓ Successfully pushed $IMAGE"
    else
        echo "❌ Failed to push $IMAGE"
    fi
done

echo
echo "=== Push Complete ==="
echo
echo "Images are now available at:"
for IMAGE in "${IMAGES[@]}"; do
    echo "  - $REGISTRY/$REPO/$IMAGE"
done