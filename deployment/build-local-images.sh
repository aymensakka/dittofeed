#!/bin/bash

# ==============================================================================
# Build Dittofeed Docker Images Locally for Testing
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check if we're in the right directory
if [ ! -f "package.json" ] || [ ! -d "packages" ]; then
    print_error "Please run from the root of the Dittofeed repository"
    exit 1
fi

print_header "Building Dittofeed Docker Images Locally"

# Build API image
print_header "Building API Image"
print_info "Building dittofeed-api:local..."

docker build \
    -f packages/api/Dockerfile \
    -t dittofeed-api:local \
    --build-arg NODE_ENV=production \
    --build-arg AUTH_MODE=multi-tenant \
    . || {
    print_error "API build failed"
    exit 1
}

print_success "API image built: dittofeed-api:local"

# Build Dashboard image
print_header "Building Dashboard Image"
print_info "Building dittofeed-dashboard:local..."

docker build \
    -f packages/dashboard/Dockerfile \
    -t dittofeed-dashboard:local \
    --build-arg NODE_ENV=production \
    --build-arg AUTH_MODE=multi-tenant \
    . || {
    print_error "Dashboard build failed"
    exit 1
}

print_success "Dashboard image built: dittofeed-dashboard:local"

# Build Worker image
print_header "Building Worker Image"
print_info "Building dittofeed-worker:local..."

docker build \
    -f packages/worker/Dockerfile \
    -t dittofeed-worker:local \
    --build-arg NODE_ENV=production \
    --build-arg AUTH_MODE=multi-tenant \
    . || {
    print_error "Worker build failed"
    exit 1
}

print_success "Worker image built: dittofeed-worker:local"

# Show built images
print_header "Built Images"
docker images | grep "dittofeed-.*local" || true

print_header "Build Complete"
print_success "All images built successfully!"
echo ""
echo "Images created:"
echo "  - dittofeed-api:local"
echo "  - dittofeed-dashboard:local"
echo "  - dittofeed-worker:local"
echo ""
echo "Next step: Run ./deployment/run-local-deployment.sh"