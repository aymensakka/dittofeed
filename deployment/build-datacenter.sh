#!/bin/bash
# Optimized build script for datacenter/VPS environments with fast connections
# Runs builds in parallel for faster completion

set -e

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
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    log_error "This script is optimized for Linux datacenter environments"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed"
    exit 1
fi

# Check if we're in the correct directory
if [ ! -f "package.json" ] || [ ! -d "packages" ]; then
    log_error "Please run this script from the root of the Dittofeed repository"
    exit 1
fi

log_info "Starting optimized datacenter build process..."

# Check system resources
log_info "System resources:"
echo "  CPUs: $(nproc)"
echo "  Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "  Available disk: $(df -h . | tail -1 | awk '{print $4}')"

# Pull latest changes
log_info "Pulling latest changes from git..."
git fetch origin
git reset --hard origin/main

# Login to registry
log_info "Logging into Docker registry..."
echo "$REGISTRY_PASS" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin

# Function to build and push in background
build_and_push_async() {
    local service=$1
    local dockerfile_path=$2
    local context_path=$3
    local image_name="$REGISTRY/$REPO/$service:$TAG"
    
    {
        log_info "[$service] Starting build..."
        
        if docker build \
            --platform "$PLATFORM" \
            -f "$dockerfile_path" \
            -t "$image_name" \
            --build-arg NODE_ENV=production \
            "$context_path" > "/tmp/build-$service.log" 2>&1; then
            
            log_info "[$service] Build completed, pushing..."
            
            if docker push "$image_name" > "/tmp/push-$service.log" 2>&1; then
                log_info "[$service] ✓ Successfully built and pushed!"
            else
                log_error "[$service] ✗ Push failed! Check /tmp/push-$service.log"
                return 1
            fi
        else
            log_error "[$service] ✗ Build failed! Check /tmp/build-$service.log"
            return 1
        fi
    } &
}

# Start all builds in parallel
log_info "Starting parallel builds (datacenter optimized)..."
build_and_push_async "api" "packages/api/Dockerfile" "."
build_and_push_async "dashboard" "packages/dashboard/Dockerfile" "."
build_and_push_async "worker" "packages/worker/Dockerfile" "."

# Wait for all background jobs to complete
log_info "Waiting for all builds to complete..."
wait

# Check results
log_info "Build summary:"
for service in api dashboard worker; do
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "$REGISTRY/$REPO/$service:$TAG"; then
        echo "  ✓ $service: built successfully"
    else
        echo "  ✗ $service: build failed"
    fi
done

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
rm -f /tmp/build-*.log /tmp/push-*.log

log_info "Datacenter build process completed!"