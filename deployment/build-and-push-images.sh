#!/bin/bash
# Build and push Dittofeed images to Nexus registry on Ubuntu VPS
# This script should be run from the root of the Dittofeed repository

set -e  # Exit on error

# Configuration
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo/dittofeed"
TAG="multitenancy-redis-v1"
PLATFORM="linux/amd64"

# Registry credentials
REGISTRY_USER="coolify-system"
REGISTRY_PASS='9sFPGGDJUFnE4z*z4Aj9'

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    log_error "This script should be run on Linux/Ubuntu VPS"
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    log_error "Node.js is not installed. Please run: ./deployment/setup-build-environment.sh"
    exit 1
fi

# Check if Yarn is installed
if ! command -v yarn &> /dev/null; then
    log_warning "Yarn is not installed. Installing Yarn..."
    npm install -g yarn
    if [ $? -ne 0 ]; then
        log_error "Failed to install Yarn. Please run: sudo npm install -g yarn"
        exit 1
    fi
    log_info "Yarn installed successfully"
fi

# Check if we're in the correct directory
if [ ! -f "package.json" ] || [ ! -d "packages" ]; then
    log_error "Please run this script from the root of the Dittofeed repository"
    exit 1
fi

log_info "Starting build process for Dittofeed images..."

# Pull latest changes (optional - comment out if building specific version)
log_info "Pulling latest changes from git..."
git fetch origin
git reset --hard origin/main
log_info "Updated to latest code"

# Login to registry
log_info "Logging into Docker registry..."
echo "$REGISTRY_PASS" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin
if [ $? -ne 0 ]; then
    log_error "Failed to login to Docker registry"
    exit 1
fi

# Note: Dependencies are installed inside Docker during build
# If you need to install dependencies locally, uncomment the following:
# log_info "Installing dependencies..."
# yarn install --frozen-lockfile

# Function to build and push an image
build_and_push() {
    local service=$1
    local dockerfile_path=$2
    local context_path=$3
    
    log_info "Building $service image..."
    
    # Full image name
    local image_name="$REGISTRY/$REPO/$service:$TAG"
    
    # Build the image
    docker build \
        --platform "$PLATFORM" \
        -f "$dockerfile_path" \
        -t "$image_name" \
        --build-arg NODE_ENV=production \
        "$context_path"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to build $service image"
        exit 1
    fi
    
    log_info "Pushing $service image to registry..."
    docker push "$image_name"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to push $service image"
        exit 1
    fi
    
    log_info "Successfully built and pushed $service image"
}

# Build and push each service
log_info "Building API service..."
build_and_push "api" "packages/api/Dockerfile" "."

log_info "Building Dashboard service..."
build_and_push "dashboard" "packages/dashboard/Dockerfile" "."

log_info "Building Worker service..."
build_and_push "worker" "packages/worker/Dockerfile" "."

# Verify images were pushed
log_info "Verifying images in registry..."
for service in api dashboard worker; do
    curl -s -u "$REGISTRY_USER:$REGISTRY_PASS" \
        "https://$REGISTRY/v2/$REPO/$service/tags/list" | \
        grep -q "$TAG"
    
    if [ $? -eq 0 ]; then
        log_info "✓ $service:$TAG verified in registry"
    else
        log_warning "⚠ Could not verify $service:$TAG in registry"
    fi
done

log_info "Build and push process completed successfully!"
log_info "Images pushed:"
echo "  - $REGISTRY/$REPO/api:$TAG"
echo "  - $REGISTRY/$REPO/dashboard:$TAG"
echo "  - $REGISTRY/$REPO/worker:$TAG"

# Cleanup
docker logout "$REGISTRY"

log_info "You can now deploy these images using Coolify"