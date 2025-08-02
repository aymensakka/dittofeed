#!/bin/bash
# Script to push Docker images with poor connectivity or large layers
# Handles timeouts and connection drops gracefully

set -e

# Configuration
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo/dittofeed"
TAG="multitenancy-redis-v1"

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

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to push with infinite retries
push_with_persistence() {
    local image=$1
    local attempt=0
    
    log_info "Starting persistent push for $image"
    log_warning "This may take a while for large images. The process will retry automatically on failure."
    
    while true; do
        attempt=$((attempt + 1))
        log_info "Push attempt #$attempt for $image"
        
        # Try to push
        if docker push "$image" 2>&1 | tee /tmp/docker-push.log; then
            log_info "Successfully pushed $image!"
            return 0
        else
            # Check the error
            if grep -q "already exists" /tmp/docker-push.log; then
                log_info "Image already fully uploaded!"
                return 0
            elif grep -q "Client Closed Request\|504 Gateway Time\|timeout" /tmp/docker-push.log; then
                log_warning "Connection dropped or timeout. Retrying in 2 seconds..."
                log_info "Docker automatically resumes from where it left off"
                sleep 2
            else
                log_error "Unexpected error. Retrying in 5 seconds..."
                sleep 5
            fi
        fi
    done
}

# Main execution
log_info "Pushing Dittofeed images to Nexus registry"
log_info "This script will retry indefinitely until successful"

# Login to registry
log_info "Logging into Docker registry..."
echo '9sFPGGDJUFnE4z*z4Aj9' | docker login "$REGISTRY" -u "coolify-system" --password-stdin

# Push each image
for service in api dashboard worker; do
    image="$REGISTRY/$REPO/$service:$TAG"
    
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^$image$"; then
        push_with_persistence "$image"
    else
        log_warning "Image $image not found locally. Skipping..."
    fi
done

log_info "All pushes completed!"

# Cleanup
rm -f /tmp/docker-push.log
docker logout "$REGISTRY"