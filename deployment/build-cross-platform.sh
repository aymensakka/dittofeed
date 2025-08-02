#!/bin/bash
# Simple cross-platform build script
# Works on both macOS (Apple Silicon) and Linux

set -e

# Configuration
REGISTRY="${DOCKER_REGISTRY:-docker.reactmotion.com}"
REPO="${DOCKER_REPO:-my-docker-repo/dittofeed}"
TAG="${IMAGE_TAG:-multitenancy-redis-v1}"
PLATFORM="${TARGET_PLATFORM:-linux/amd64}"

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Building on macOS for $PLATFORM"
    NEED_BUILDX=true
else
    echo "Building on Linux"
    NEED_BUILDX=false
fi

# Simple build function
build_image() {
    local service=$1
    echo "Building $service..."
    
    if [ "$NEED_BUILDX" = true ]; then
        # Use buildx for cross-platform on Mac
        docker buildx build \
            --platform "$PLATFORM" \
            --load \
            -f "packages/$service/Dockerfile" \
            -t "$REGISTRY/$REPO/$service:$TAG" \
            .
    else
        # Regular build on Linux
        docker build \
            -f "packages/$service/Dockerfile" \
            -t "$REGISTRY/$REPO/$service:$TAG" \
            .
    fi
}

# Build all services
for service in api dashboard worker; do
    build_image "$service"
done

echo "Build complete! Images built:"
docker images | grep "$REPO" | grep "$TAG"

echo ""
echo "To push images, run:"
echo "  docker push $REGISTRY/$REPO/api:$TAG"
echo "  docker push $REGISTRY/$REPO/dashboard:$TAG"
echo "  docker push $REGISTRY/$REPO/worker:$TAG"