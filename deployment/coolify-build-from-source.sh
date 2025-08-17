#!/bin/bash
# Coolify build script - builds images from source with migrations included
set -e

echo "=== Starting Coolify Build from Source ==="

# Configuration
TAG="multitenancy-$(date +%Y%m%d-%H%M%S)"

# Step 1: Build API image
echo "Building API image..."
docker build -f packages/api/Dockerfile \
    -t dittofeed-api:$TAG \
    --build-arg NODE_ENV=production \
    --build-arg AUTH_MODE=multi-tenant \
    .

# Step 2: Build Dashboard image  
echo "Building Dashboard image..."
docker build -f packages/dashboard/Dockerfile \
    -t dittofeed-dashboard:$TAG \
    --build-arg NODE_ENV=production \
    --build-arg AUTH_MODE=multi-tenant \
    .

# Step 3: Build Worker image
echo "Building Worker image..."
docker build -f packages/worker/Dockerfile \
    -t dittofeed-worker:$TAG \
    --build-arg NODE_ENV=production \
    --build-arg AUTH_MODE=multi-tenant \
    .

# Step 4: Tag images for deployment
docker tag dittofeed-api:$TAG dittofeed-api:latest
docker tag dittofeed-dashboard:$TAG dittofeed-dashboard:latest  
docker tag dittofeed-worker:$TAG dittofeed-worker:latest

echo "=== Build complete ==="
echo "Images built:"
echo "  - dittofeed-api:latest"
echo "  - dittofeed-dashboard:latest"
echo "  - dittofeed-worker:latest"