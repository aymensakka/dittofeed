#!/bin/bash
# Push Dittofeed embedded dashboard images to Docker registry
# This script pushes already-built local images to the registry
# Usage: ./push-embedded-images.sh [registry] [repo] [tag]

set -e  # Exit on error

# Default configuration
DEFAULT_REGISTRY="docker.reactmotion.com"
DEFAULT_REPO="my-docker-repo/dittofeed"
DEFAULT_TAG="embedded-final"

# Use provided arguments or defaults
REGISTRY="${1:-$DEFAULT_REGISTRY}"
REPO="${2:-$DEFAULT_REPO}"
TAG="${3:-$DEFAULT_TAG}"

# Local image names (as built on the server)
LOCAL_API="aymensakka/dittofeed-api:embedded-final"
LOCAL_DASHBOARD="aymensakka/dittofeed-dashboard:embedded-final"
LOCAL_WORKER="aymensakka/dittofeed-worker:embedded-final"

# Registry credentials (update these or use environment variables)
REGISTRY_USER="${DOCKER_REGISTRY_USER:-coolify-system}"
REGISTRY_PASS="${DOCKER_REGISTRY_PASS:-9sFPGGDJUFnE4z*z4Aj9}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if image exists locally
check_local_image() {
    local image=$1
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${image}$"; then
        return 0
    else
        return 1
    fi
}

# Function to push with retry logic
push_with_retry() {
    local source_image=$1
    local target_image=$2
    local max_attempts=3
    local attempt=0
    
    log_info "Pushing $target_image..."
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        log_info "Attempt #$attempt"
        
        if docker push "$target_image"; then
            log_info "✓ Successfully pushed $target_image"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warning "Push failed. Retrying in 5 seconds..."
            sleep 5
        fi
    done
    
    log_error "Failed to push $target_image after $max_attempts attempts"
    return 1
}

# Main script starts here
log_info "=== Dittofeed Embedded Dashboard Image Push ==="
log_info "Registry: $REGISTRY"
log_info "Repository: $REPO"
log_info "Tag: $TAG"
echo ""

# Step 1: Check if all local images exist
log_step "1/4: Checking local images..."
missing_images=()

for image in "$LOCAL_API" "$LOCAL_DASHBOARD" "$LOCAL_WORKER"; do
    if check_local_image "$image"; then
        log_info "✓ Found: $image"
    else
        log_error "✗ Missing: $image"
        missing_images+=("$image")
    fi
done

if [ ${#missing_images[@]} -gt 0 ]; then
    log_error "Missing required images. Please build them first:"
    for img in "${missing_images[@]}"; do
        echo "  - $img"
    done
    echo ""
    echo "Run the build commands:"
    echo "  docker build --platform linux/amd64 -f packages/api/Dockerfile -t aymensakka/dittofeed-api:embedded-final ."
    echo "  docker build --platform linux/amd64 -f packages/dashboard/Dockerfile -t aymensakka/dittofeed-dashboard:embedded-final ."
    echo "  docker build --platform linux/amd64 -f packages/worker/Dockerfile -t aymensakka/dittofeed-worker:embedded-final ."
    exit 1
fi

# Step 2: Login to registry
log_step "2/4: Logging into Docker registry..."
echo "$REGISTRY_PASS" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin
if [ $? -ne 0 ]; then
    log_error "Failed to login to Docker registry"
    log_info "Try logging in manually: docker login $REGISTRY"
    exit 1
fi
log_info "✓ Successfully logged into registry"

# Step 3: Tag images for registry
log_step "3/4: Tagging images for registry..."
declare -A image_map=(
    ["$LOCAL_API"]="$REGISTRY/$REPO/api:$TAG"
    ["$LOCAL_DASHBOARD"]="$REGISTRY/$REPO/dashboard:$TAG"
    ["$LOCAL_WORKER"]="$REGISTRY/$REPO/worker:$TAG"
)

for local_image in "${!image_map[@]}"; do
    target_image="${image_map[$local_image]}"
    log_info "Tagging $local_image as $target_image"
    docker tag "$local_image" "$target_image"
    if [ $? -ne 0 ]; then
        log_error "Failed to tag $local_image"
        exit 1
    fi
done
log_info "✓ All images tagged successfully"

# Step 4: Push images to registry
log_step "4/4: Pushing images to registry..."
failed_pushes=()

for local_image in "${!image_map[@]}"; do
    target_image="${image_map[$local_image]}"
    if ! push_with_retry "$local_image" "$target_image"; then
        failed_pushes+=("$target_image")
    fi
done

# Summary
echo ""
log_info "=== Push Summary ==="
if [ ${#failed_pushes[@]} -eq 0 ]; then
    log_info "✓ All images pushed successfully!"
    log_info "Images available at:"
    for target in "${image_map[@]}"; do
        echo "  - $target"
    done
    echo ""
    log_info "You can now deploy these images in Coolify or docker-compose"
else
    log_error "Some images failed to push:"
    for img in "${failed_pushes[@]}"; do
        echo "  - $img"
    done
    echo ""
    log_info "To retry individual images, use:"
    for img in "${failed_pushes[@]}"; do
        echo "  ./deployment/push-single-image.sh $img"
    done
    exit 1
fi

# Cleanup
docker logout "$REGISTRY"
log_info "Logged out from registry"