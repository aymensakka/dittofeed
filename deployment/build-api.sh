#!/bin/bash
# Build and push API service to Nexus
# Now includes multi-tenant OAuth authentication support

set -e

# Configuration
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo/dittofeed"
TAG="multitenancy-redis-v1"
SERVICE="api"

# Registry credentials
REGISTRY_USER="coolify-system"
REGISTRY_PASS='9sFPGGDJUFnE4z*z4Aj9'

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check directory
if [ ! -f "package.json" ] || [ ! -d "packages" ]; then
    log_error "Please run from the root of the Dittofeed repository"
    exit 1
fi

log_info "Building API service..."

# Login to registry
log_info "Logging into Docker registry..."
echo "$REGISTRY_PASS" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin

# Build the image
log_info "Building API image for linux/amd64..."
docker build \
    --platform linux/amd64 \
    -f packages/api/Dockerfile \
    -t "$REGISTRY/$REPO/$SERVICE:$TAG" \
    --build-arg NODE_ENV=production \
    .

if [ $? -eq 0 ]; then
    log_info "API build successful"
else
    log_error "API build failed"
    exit 1
fi

# Push the image
log_info "Pushing API image to Nexus..."
if docker push "$REGISTRY/$REPO/$SERVICE:$TAG"; then
    log_info "✓ API image pushed successfully"
else
    log_error "Failed to push API image"
    log_info "Retry with: ./deployment/push-single-image.sh $REGISTRY/$REPO/$SERVICE:$TAG"
    exit 1
fi

# Verify
if curl -sf -u "$REGISTRY_USER:$REGISTRY_PASS" \
    "https://$REGISTRY/v2/$REPO/$SERVICE/tags/list" | grep -q "$TAG"; then
    log_info "✓ API image verified in registry"
else
    log_error "Could not verify API image in registry"
fi

docker logout "$REGISTRY"
log_info "API build and push completed!"