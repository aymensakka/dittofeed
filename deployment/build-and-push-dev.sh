#!/bin/bash
# Build and push script for dev server
# Uses docker-compose to build and push all images

set -e

# Configuration
REGISTRY="docker.reactmotion.com"
REGISTRY_USER="coolify-system"
REGISTRY_PASS='9sFPGGDJUFnE4z*z4Aj9'

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the correct directory
if [ ! -f "docker-compose.build.yaml" ]; then
    log_error "docker-compose.build.yaml not found. Run from project root."
    exit 1
fi

log_info "Dev Server Build & Push Process"
echo "================================"

# Login to registry
log_info "Logging into Docker registry..."
echo "$REGISTRY_PASS" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin

# Pull latest code
log_info "Pulling latest code..."
git pull origin main

# Build all images using docker-compose
log_info "Building all images..."
docker-compose -f docker-compose.build.yaml build --parallel

# Push all images to Nexus
log_info "Pushing images to Nexus registry..."
docker-compose -f docker-compose.build.yaml push

# Verify push
log_info "Verifying images in registry..."
for service in api dashboard worker; do
    if curl -sf -u "$REGISTRY_USER:$REGISTRY_PASS" \
        "https://$REGISTRY/v2/my-docker-repo/dittofeed/$service/tags/list" | grep -q "multitenancy-redis-v1"; then
        echo "  ✓ $service: verified in registry"
    else
        echo "  ✗ $service: not found in registry"
    fi
done

# Cleanup
docker logout "$REGISTRY"

log_info "Build and push completed!"
log_info "Images are ready for deployment via Coolify"