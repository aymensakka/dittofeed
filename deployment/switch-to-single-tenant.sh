#!/bin/bash

echo "======================================"
echo "Switching to Single-Tenant Mode"
echo "======================================"
echo ""
echo "Multi-tenant auth is not implemented in the API."
echo "Switching to single-tenant mode for working authentication."
echo ""

# Update the build script for single-tenant
cat > /tmp/build-dashboard-single-tenant.sh << 'EOF'
#!/bin/bash
set -e

# Configuration
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo/dittofeed"
TAG="single-tenant-v1"
SERVICE="dashboard"

# Registry credentials
REGISTRY_USER="coolify-system"
REGISTRY_PASS='9sFPGGDJUFnE4z*z4Aj9'

echo "Building Dashboard for SINGLE-TENANT mode..."

# Login to registry
echo "$REGISTRY_PASS" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin

# Build with single-tenant mode
docker build \
    --platform linux/amd64 \
    -f packages/dashboard/Dockerfile \
    -t "$REGISTRY/$REPO/$SERVICE:$TAG" \
    --build-arg NODE_ENV=production \
    --build-arg NEXT_PUBLIC_API_BASE_URL=https://communication-api.caramelme.com \
    --build-arg NEXT_PUBLIC_API_URL=https://communication-api.caramelme.com \
    --build-arg NEXT_PUBLIC_AUTH_MODE=single-tenant \
    .

# Push the image
docker push "$REGISTRY/$REPO/$SERVICE:$TAG"

docker logout "$REGISTRY"
echo "Single-tenant dashboard build complete!"
EOF

chmod +x /tmp/build-dashboard-single-tenant.sh
mv /tmp/build-dashboard-single-tenant.sh deployment/build-dashboard-single-tenant.sh

echo "Created: deployment/build-dashboard-single-tenant.sh"
echo ""

echo "======================================"
echo "Instructions"
echo "======================================"
echo ""
echo "1. BUILD the single-tenant dashboard:"
echo "   cd ~/dittofeed"
echo "   ./deployment/build-dashboard-single-tenant.sh"
echo ""
echo "2. UPDATE Coolify environment variables:"
echo "   AUTH_MODE=single-tenant"
echo "   NEXT_PUBLIC_AUTH_MODE=single-tenant"
echo "   PASSWORD=your-secure-password"
echo ""
echo "3. UPDATE Docker image in Coolify:"
echo "   Change dashboard image tag from 'multitenancy-redis-v1' to 'single-tenant-v1'"
echo ""
echo "4. REDEPLOY in Coolify"
echo ""
echo "5. ACCESS the dashboard:"
echo "   https://communication-dashboard.caramelme.com/dashboard/auth/single-tenant"
echo "   Password: [whatever you set in step 2]"
echo ""
echo "======================================"
echo "Why This Is Necessary"
echo "======================================"
echo ""
echo "The Dittofeed codebase only implements authentication for single-tenant mode."
echo "Multi-tenant OAuth routes (/api/public/auth/oauth2/*) don't exist in the code."
echo ""
echo "Single-tenant mode provides:"
echo "- Working authentication with password"
echo "- Access to all dashboard features"
echo "- Simplified deployment"
echo ""