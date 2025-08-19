#!/bin/bash
# Build and push Dittofeed images to Nexus registry on Ubuntu VPS
# This script should be run from the root of the Dittofeed repository
# Now includes multi-tenant OAuth authentication support

set -e  # Exit on error

# Configuration
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo/dittofeed"
TAG="multitenancy-redis-v1"
# Or use dynamic versioning:
# TAG="multitenancy-redis-$(date +%Y%m%d-%H%M%S)"
# TAG="multitenancy-redis-$(git rev-parse --short HEAD)"
PLATFORM="linux/amd64"

# Note: Docker build doesn't support CPU/memory limits
# These would only apply at runtime, not build time
# For 2 vCPU servers, we rely on sequential builds and cache cleanup

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

# Check system resources
log_info "System resources:"
echo "  CPUs: $(nproc)"
echo "  Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "  Note: Building sequentially to avoid resource exhaustion"

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
    
    # Build the image with appropriate args
    if [ "$service" = "dashboard" ]; then
        # Dashboard needs special build args for multi-tenant mode
        docker build \
            --platform "$PLATFORM" \
            -f "$dockerfile_path" \
            -t "$image_name" \
            --build-arg NODE_ENV=production \
            --build-arg NEXT_PUBLIC_API_BASE_URL=https://communication-api.caramelme.com \
            --build-arg NEXT_PUBLIC_API_URL=https://communication-api.caramelme.com \
            --build-arg NEXT_PUBLIC_AUTH_MODE=multi-tenant \
            "$context_path"
    else
        # Standard build for other services
        docker build \
            --platform "$PLATFORM" \
            -f "$dockerfile_path" \
            -t "$image_name" \
            --build-arg NODE_ENV=production \
            "$context_path"
    fi
    
    if [ $? -ne 0 ]; then
        log_error "Failed to build $service image"
        exit 1
    fi
    
    log_info "Pushing $service image to registry..."
    
    # Push image - datacenter connection should handle this fine
    if docker push "$image_name"; then
        log_info "Successfully pushed $service image"
    else
        log_error "Failed to push $service image"
        log_error "If this is a timeout issue, run: ./deployment/push-single-image.sh $image_name"
        exit 1
    fi
    
    log_info "Successfully built and pushed $service image"
}

# Build and push each service (sequential to avoid OOM on 2 vCPU server)
log_info "Building services sequentially to avoid resource exhaustion..."

log_info "Building API service (with OAuth support)..."
build_and_push "api" "packages/api/Dockerfile" "."

log_info "Building Dashboard service (multi-tenant mode)..."
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