#!/bin/bash
# Build and push Dashboard service to Nexus

set -e

# Configuration
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo/dittofeed"
TAG="multitenancy-redis-v1"
SERVICE="dashboard"

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

log_info "Building Dashboard service..."

# Login to registry
log_info "Logging into Docker registry..."
echo "$REGISTRY_PASS" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin

# Ensure we have the latest fixed next.config.js
log_info "Verifying next.config.js is fixed..."
if grep -q "basePath: false" packages/dashboard/next.config.js; then
    log_error "next.config.js still has the conflicting redirect!"
    log_info "Applying fix..."
    sed -i.bak '/{$/{N;/basePath: false/d;}' packages/dashboard/next.config.js
fi

# Build the image with correct API URL
log_info "Building Dashboard image for linux/amd64..."
log_info "Setting NEXT_PUBLIC_API_BASE_URL=https://communication-api.caramelme.com"
docker build \
    --platform linux/amd64 \
    -f packages/dashboard/Dockerfile \
    -t "$REGISTRY/$REPO/$SERVICE:$TAG" \
    --build-arg NODE_ENV=production \
    --build-arg NEXT_PUBLIC_API_BASE_URL=https://communication-api.caramelme.com \
    --build-arg NEXT_PUBLIC_API_URL=https://communication-api.caramelme.com \
    --build-arg NEXT_PUBLIC_AUTH_MODE=multi-tenant \
    .

if [ $? -eq 0 ]; then
    log_info "Dashboard build successful"
else
    log_error "Dashboard build failed"
    exit 1
fi

# Push the image
log_info "Pushing Dashboard image to Nexus..."
if docker push "$REGISTRY/$REPO/$SERVICE:$TAG"; then
    log_info "✓ Dashboard image pushed successfully"
else
    log_error "Failed to push Dashboard image"
    log_info "Retry with: ./deployment/push-single-image.sh $REGISTRY/$REPO/$SERVICE:$TAG"
    exit 1
fi

# Verify
if curl -sf -u "$REGISTRY_USER:$REGISTRY_PASS" \
    "https://$REGISTRY/v2/$REPO/$SERVICE/tags/list" | grep -q "$TAG"; then
    log_info "✓ Dashboard image verified in registry"
else
    log_error "Could not verify Dashboard image in registry"
fi

docker logout "$REGISTRY"
log_info "Dashboard build and push completed!"