#!/bin/bash
# Build Dittofeed images on macOS for linux/amd64 deployment
# This script uses Docker buildx to cross-compile for Linux on Mac

set -e

# Configuration
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo/dittofeed"
TAG="multitenancy-redis-v1"
PLATFORM="linux/amd64"  # Target platform for Ubuntu deployment

# Registry credentials
REGISTRY_USER="coolify-system"
REGISTRY_PASS='9sFPGGDJUFnE4z*z4Aj9'

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_platform() {
    echo -e "${BLUE}[PLATFORM]${NC} $1"
}

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_error "This script is designed for macOS. Use build-and-push-images.sh on Linux."
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    log_error "Docker Desktop is not installed. Please install Docker Desktop for Mac."
    exit 1
fi

# Check if we're in the correct directory
if [ ! -f "package.json" ] || [ ! -d "packages" ]; then
    log_error "Please run this script from the root of the Dittofeed repository"
    exit 1
fi

log_info "Starting cross-platform build on macOS for linux/amd64..."
log_platform "Building on: $(uname -m) ($(sw_vers -productName) $(sw_vers -productVersion))"
log_platform "Target platform: $PLATFORM"

# Ensure buildx is available and set up
log_info "Setting up Docker buildx..."
docker buildx version >/dev/null 2>&1 || {
    log_error "Docker buildx not available. Please update Docker Desktop."
    exit 1
}

# Create and use a new buildx builder for cross-platform builds
BUILDER_NAME="dittofeed-cross-platform"
if ! docker buildx inspect $BUILDER_NAME >/dev/null 2>&1; then
    log_info "Creating cross-platform builder..."
    docker buildx create --name $BUILDER_NAME --driver docker-container --use
else
    log_info "Using existing cross-platform builder..."
    docker buildx use $BUILDER_NAME
fi

# Ensure the builder is running
docker buildx inspect --bootstrap >/dev/null 2>&1

# Login to registry
log_info "Logging into Docker registry..."
echo "$REGISTRY_PASS" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin

# Function to build and push an image
build_and_push_cross_platform() {
    local service=$1
    local dockerfile_path=$2
    local context_path=$3
    
    log_info "Building $service for $PLATFORM..."
    log_warning "This will be slower than native builds due to emulation"
    
    # Full image name
    local image_name="$REGISTRY/$REPO/$service:$TAG"
    
    # Build and push in one step (more efficient for cross-platform)
    if docker buildx build \
        --platform "$PLATFORM" \
        -f "$dockerfile_path" \
        -t "$image_name" \
        --build-arg NODE_ENV=production \
        --push \
        --progress=plain \
        "$context_path"; then
        
        log_info "✓ Successfully built and pushed $service for $PLATFORM"
    else
        log_error "✗ Failed to build $service"
        return 1
    fi
}

# Show current Docker context
log_info "Docker context:"
docker context show
echo "  Builder: $(docker buildx inspect --bootstrap | grep Name | head -1)"

# Pull latest changes (optional)
read -p "Pull latest changes from git? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Pulling latest changes..."
    git fetch origin
    git reset --hard origin/main
fi

# Build all services
log_info "Building all services for $PLATFORM deployment..."
log_warning "Cross-platform builds are slower due to emulation. Please be patient."

# Build services sequentially
build_and_push_cross_platform "api" "packages/api/Dockerfile" "."
build_and_push_cross_platform "dashboard" "packages/dashboard/Dockerfile" "."
build_and_push_cross_platform "worker" "packages/worker/Dockerfile" "."

# Verify in registry
log_info "Verifying images in registry..."
for service in api dashboard worker; do
    if curl -sf -u "$REGISTRY_USER:$REGISTRY_PASS" \
        "https://$REGISTRY/v2/$REPO/$service/tags/list" | grep -q "$TAG"; then
        echo "  ✓ $service: verified in registry"
    else
        echo "  ✗ $service: not found in registry"
    fi
done

# Cleanup
docker logout "$REGISTRY"

# Switch back to default builder
docker buildx use default

log_info "Cross-platform build completed!"
log_platform "Images built for $PLATFORM and pushed to registry"
log_info "These images can now be deployed on Ubuntu/Linux servers"

# Performance tip
echo
log_warning "Performance tip: Building on the target platform (Ubuntu VPS) is much faster."
log_warning "Consider using ./deployment/build-and-push-images.sh directly on your Ubuntu server."