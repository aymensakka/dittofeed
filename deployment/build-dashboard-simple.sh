#!/bin/bash

# ==============================================================================
# Simple Dashboard Build with Required Environment Variables
# ==============================================================================

set -e

echo "===================================================="
echo "Building Dashboard with Multi-tenant Auth Mode"
echo "===================================================="
echo ""

# Registry and image settings
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo/dittofeed"
TAG="multitenancy-oauth-v2"
IMAGE="${REGISTRY}/${REPO}/dashboard:${TAG}"

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    echo "❌ Error: package.json not found. Please run from the dittofeed root directory."
    exit 1
fi

echo "Step 1: Setting build environment variables..."
echo "----------------------------------------------"
# Set all required environment variables for the build
export NODE_ENV=production
export AUTH_MODE=multi-tenant
export NEXT_PUBLIC_AUTH_MODE=multi-tenant
export NEXT_PUBLIC_ENABLE_MULTITENANCY=true

# Add required ClickHouse config to pass validation
export CLICKHOUSE_HOST=clickhouse
export CLICKHOUSE_USER=dittofeed
export CLICKHOUSE_PASSWORD=password

echo "Environment variables set:"
echo "  NODE_ENV=production"
echo "  AUTH_MODE=multi-tenant"
echo "  NEXT_PUBLIC_AUTH_MODE=multi-tenant"
echo "  CLICKHOUSE_HOST=clickhouse"
echo ""

echo "Step 2: Installing dependencies and building all packages..."
echo "-------------------------------------------------------------"
# First install all dependencies
yarn install

# Build all dependent packages in correct order
echo "Building isomorphic-lib package..."
yarn workspace isomorphic-lib build

echo "Building backend-lib package..."
yarn workspace backend-lib build

echo "Building emailo package..."
yarn workspace emailo build

echo "Step 3: Building dashboard locally with yarn..."
echo "------------------------------------------------"
cd packages/dashboard

# Build with environment variables
yarn build || {
    echo "❌ Build failed. Trying with minimal config..."
    
    # Create a minimal env file for the build
    cat > .env.production << EOF
NODE_ENV=production
AUTH_MODE=multi-tenant
NEXT_PUBLIC_AUTH_MODE=multi-tenant
NEXT_PUBLIC_ENABLE_MULTITENANCY=true
CLICKHOUSE_HOST=clickhouse
CLICKHOUSE_USER=dittofeed
CLICKHOUSE_PASSWORD=password
EOF
    
    yarn build || {
        echo "❌ Build still failed"
        exit 1
    }
}

cd ../..

echo "✅ Dashboard built successfully"
echo ""

echo "Step 4: Building Docker image..."
echo "---------------------------------"
# Use the standard Dockerfile since we've already built it
docker build \
    --platform linux/amd64 \
    -f packages/dashboard/Dockerfile \
    -t "$IMAGE" \
    --build-arg AUTH_MODE=multi-tenant \
    --build-arg NEXT_PUBLIC_AUTH_MODE=multi-tenant \
    . || {
    echo "❌ Failed to build Docker image"
    exit 1
}

echo "✅ Docker image built: $IMAGE"
echo ""

echo "Step 5: Logging into Docker registry..."
echo "----------------------------------------"
docker login "$REGISTRY" --username coolify-system --password '9sFPGGDJUFnE4z*z4Aj9' || {
    echo "❌ Failed to login to registry"
    exit 1
}
echo "✅ Logged into Docker registry"
echo ""

echo "Step 6: Pushing image to registry..."
echo "-------------------------------------"
docker push "$IMAGE" || {
    echo "❌ Failed to push image"
    exit 1
}
echo "✅ Image pushed to registry"
echo ""

echo "===================================================="
echo "Dashboard Build Complete!"
echo "===================================================="
echo ""
echo "Image: $IMAGE"
echo ""
echo "Next steps:"
echo "1. Update the dashboard image in Coolify to:"
echo "   $IMAGE"
echo ""
echo "2. Ensure these runtime environment variables are set in Coolify:"
echo "   AUTH_MODE=multi-tenant"
echo "   NEXT_PUBLIC_AUTH_MODE=multi-tenant"
echo "   GOOGLE_CLIENT_ID=<your-google-client-id>"
echo "   GOOGLE_CLIENT_SECRET=<your-google-client-secret>"
echo "   NEXTAUTH_URL=https://communication-dashboard.caramelme.com/dashboard"
echo "   NEXTAUTH_SECRET=<your-nextauth-secret>"
echo ""
echo "3. Redeploy the dashboard service in Coolify"
echo ""
echo "The dashboard now has multi-tenant auth mode compiled in!"
echo "===================================================="