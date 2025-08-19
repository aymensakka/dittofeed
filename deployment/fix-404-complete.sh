#!/bin/bash

echo "======================================"
echo "Complete 404 Fix for Dashboard"
echo "======================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Find containers
DASHBOARD=$(docker ps --format '{{.Names}}' | grep -i dashboard | head -1)
API=$(docker ps --format '{{.Names}}' | grep -i api | head -1)
POSTGRES=$(docker ps -q -f name=postgres | head -1)

if [ -z "$DASHBOARD" ]; then
    echo -e "${RED}Dashboard container not running!${NC}"
    
    # Try to start it
    DASHBOARD_STOPPED=$(docker ps -a --format '{{.Names}}' | grep -i dashboard | head -1)
    if [ ! -z "$DASHBOARD_STOPPED" ]; then
        echo "Found stopped dashboard: $DASHBOARD_STOPPED"
        echo "Starting it..."
        docker start $DASHBOARD_STOPPED
        sleep 10
        DASHBOARD=$DASHBOARD_STOPPED
    else
        echo "No dashboard container found at all!"
        exit 1
    fi
fi

echo "Dashboard container: $DASHBOARD"
echo ""

echo "Step 1: Checking current environment..."
echo "----------------------------------------"

# Check auth mode
AUTH_MODE=$(docker exec $DASHBOARD env | grep "^NEXT_PUBLIC_AUTH_MODE=" | cut -d= -f2)
echo "NEXT_PUBLIC_AUTH_MODE: $AUTH_MODE"

if [ "$AUTH_MODE" != "multi-tenant" ]; then
    echo -e "${YELLOW}WARNING: Auth mode is not multi-tenant!${NC}"
fi

# Check workspace
WORKSPACE_NAME=$(docker exec $DASHBOARD env | grep "BOOTSTRAP_WORKSPACE_NAME" | cut -d= -f2)
echo "BOOTSTRAP_WORKSPACE_NAME: $WORKSPACE_NAME"

echo ""
echo "Step 2: Fixing Next.js configuration..."
echo "----------------------------------------"

# Create the correct next.config.js
cat > /tmp/next.config.js << 'EOF'
const path = require("path");

/** @type {import('next').NextConfig} */
const nextConfig = {
  typescript: {
    tsconfigPath: "./tsconfig.build.json",
  },
  basePath: "/dashboard",
  output: process.env.NEXT_STANDALONE !== "false" ? "standalone" : undefined,
  pageExtensions: ["page.tsx", "page.ts"],
  poweredByHeader: false,
  reactStrictMode: true,
  transpilePackages: ["isomorphic-lib", "backend-lib"],
  eslint: {
    ignoreDuringBuilds: true,
  },
  swcMinify: true,
  images: {
    domains: ["*"],
  },
  async headers() {
    return [
      {
        source: "/public/:path*",
        headers: [{ key: "Access-Control-Allow-Origin", value: "*" }],
      },
    ];
  },
  async redirects() {
    return [
      {
        source: "/",
        destination: "/journeys",
        permanent: false,
      },
    ];
  },
  experimental: {
    newNextLinkBehavior: true,
    instrumentationHook: true,
    outputFileTracingRoot: path.join(__dirname, "../../"),
  },
};

console.log("nextConfig", nextConfig);
module.exports = nextConfig;
EOF

echo "Copying fixed config to container..."

# Try multiple possible locations
docker cp /tmp/next.config.js ${DASHBOARD}:/app/packages/dashboard/next.config.js 2>/dev/null
docker cp /tmp/next.config.js ${DASHBOARD}:/app/next.config.js 2>/dev/null

echo "Config updated"
echo ""

echo "Step 3: Checking Next.js build..."
echo "----------------------------------"

# Check if .next directory exists
docker exec $DASHBOARD ls -la /app/.next 2>/dev/null && echo ".next directory found" || {
    docker exec $DASHBOARD ls -la /app/packages/dashboard/.next 2>/dev/null && echo ".next directory found in packages/dashboard" || echo "No .next directory found!"
}

echo ""
echo "Step 4: Checking running processes..."
echo "--------------------------------------"
docker exec $DASHBOARD ps aux | grep -E "node|next" | head -5

echo ""
echo "Step 5: Restarting dashboard..."
echo "--------------------------------"
docker restart $DASHBOARD
echo "Waiting for restart..."
sleep 15

echo ""
echo "Step 6: Testing internal routes..."
echo "-----------------------------------"

DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD 2>/dev/null | head -c -1)
echo "Dashboard IP: $DASHBOARD_IP"

# Test from API container if available
if [ ! -z "$API" ]; then
    echo -n "Testing / : "
    docker exec $API curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://$DASHBOARD_IP:3000/" 2>/dev/null || echo "Failed"
    
    echo -n "Testing /dashboard : "
    docker exec $API curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://$DASHBOARD_IP:3000/dashboard" 2>/dev/null || echo "Failed"
    
    echo -n "Testing /dashboard/journeys : "
    RESPONSE=$(docker exec $API curl -s -w "\nHTTP_CODE:%{http_code}" "http://$DASHBOARD_IP:3000/dashboard/journeys" 2>/dev/null || echo "Failed")
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
    echo "HTTP $HTTP_CODE"
    
    if [ "$HTTP_CODE" = "404" ]; then
        echo ""
        echo -e "${YELLOW}Still getting 404. Checking response:${NC}"
        echo "$RESPONSE" | head -20
    fi
fi

echo ""
echo "Step 7: Checking dashboard logs..."
echo "-----------------------------------"
docker logs $DASHBOARD --tail 30 2>&1 | grep -v "Compiled\|wait" | tail -20

echo ""
echo "Step 8: Verifying workspace exists..."
echo "--------------------------------------"
if [ ! -z "$POSTGRES" ]; then
    echo "Workspaces in database:"
    docker exec $POSTGRES psql -U dittofeed -d dittofeed -c "SELECT id, name, type FROM \"Workspace\";" 2>/dev/null
fi

echo ""
echo "Step 9: Updating Cloudflare tunnel..."
echo "--------------------------------------"

if [ ! -z "$API" ]; then
    API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API 2>/dev/null | head -c -1)
    echo "API IP: $API_IP"
    echo "Dashboard IP: $DASHBOARD_IP"
    
    # Update cloudflare config
    CLOUDFLARED=$(docker ps --format '{{.Names}}' | grep -i cloudflared | head -1)
    if [ ! -z "$CLOUDFLARED" ]; then
        cat > /tmp/cloudflared-config.yml << EOF
tunnel: auto
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: communication-api.caramelme.com
    service: http://${API_IP}:3001
    originRequest:
      noTLSVerify: true
      
  - hostname: communication-dashboard.caramelme.com
    service: http://${DASHBOARD_IP}:3000
    originRequest:
      noTLSVerify: true
      
  - service: http_status:404
EOF
        docker cp /tmp/cloudflared-config.yml ${CLOUDFLARED}:/etc/cloudflared/config.yml
        docker restart ${CLOUDFLARED}
        echo "Cloudflare tunnel updated"
    fi
fi

echo ""
echo "Step 10: Final external test..."
echo "--------------------------------"
sleep 5

echo -n "Dashboard (https://communication-dashboard.caramelme.com): "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://communication-dashboard.caramelme.com" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "307" ]; then
    echo -e "${GREEN}✓ HTTP $HTTP_CODE${NC}"
else
    echo -e "${RED}✗ HTTP $HTTP_CODE${NC}"
fi

echo ""
echo "======================================"
echo "Diagnostic Complete"
echo "======================================"

if [ "$HTTP_CODE" = "404" ]; then
    echo ""
    echo -e "${YELLOW}The 404 issue persists. This might be because:${NC}"
    echo ""
    echo "1. The dashboard image was built with the wrong next.config.js"
    echo "   Solution: Rebuild the dashboard image with the fix"
    echo ""
    echo "2. The Next.js app is not finding the pages"
    echo "   Solution: Check if NODE_ENV is set correctly"
    echo ""
    echo "3. There's an authentication issue in multi-tenant mode"
    echo "   Solution: Check if auth providers are configured"
    echo ""
    echo "To rebuild the dashboard with the fix:"
    echo "  1. On your build server:"
    echo "     cd dittofeed"
    echo "     git fetch origin"
    echo "     git reset --hard origin/main"
    echo "     ./deployment/build-dashboard.sh"
    echo "  2. Update the image in Coolify"
    echo "  3. Redeploy"
else
    echo -e "${GREEN}✓ Dashboard is working!${NC}"
    echo ""
    echo "Access your application at:"
    echo "https://communication-dashboard.caramelme.com"
fi