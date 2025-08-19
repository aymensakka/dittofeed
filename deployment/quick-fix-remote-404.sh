#!/bin/bash

echo "======================================"
echo "Quick Fix for Dashboard 404 on Remote"
echo "======================================"
echo ""
echo "This script applies the Next.js config fix directly to the running container"
echo ""

# Get dashboard container name
DASHBOARD=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*p0gcsc088cogco0cokco4404" | head -1)

if [ -z "$DASHBOARD" ]; then
    echo "❌ Dashboard container not found"
    exit 1
fi

echo "Found dashboard container: $DASHBOARD"
echo ""

echo "Step 1: Creating fixed next.config.js..."
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
    // already performed in CI, redundant
    ignoreDuringBuilds: true,
  },
  swcMinify: true,
  images: {
    domains: ["*"],
  },
  async headers() {
    return [
      {
        // Apply CORS headers to /dashboard/public path
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

echo "✅ Fixed config created"
echo ""

echo "Step 2: Backing up current config in container..."
docker exec $DASHBOARD cp /app/packages/dashboard/next.config.js /app/packages/dashboard/next.config.js.backup 2>/dev/null || echo "Backup skipped"
echo ""

echo "Step 3: Copying fixed config to container..."
docker cp /tmp/next.config.js ${DASHBOARD}:/app/packages/dashboard/next.config.js
if [ $? -eq 0 ]; then
    echo "✅ Fixed config copied to container"
else
    echo "❌ Failed to copy config"
    exit 1
fi
echo ""

echo "Step 4: Restarting dashboard container..."
docker restart $DASHBOARD > /dev/null 2>&1
echo "✅ Container restarted"
echo ""

echo "Step 5: Waiting for service to start..."
for i in {1..30}; do
    echo -n "."
    sleep 1
done
echo ""
echo ""

echo "Step 6: Testing dashboard routes..."
echo "-----------------------------------"

# Get dashboard IP
DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD 2>/dev/null | head -c -1)
echo "Dashboard IP: $DASHBOARD_IP"
echo ""

# Find an API container to test from
API=$(docker ps --format '{{.Names}}' | grep -E "api.*p0gcsc088cogco0cokco4404" | head -1)

if [ ! -z "$API" ]; then
    echo -n "Testing /dashboard : "
    HTTP_CODE=$(docker exec $API curl -s -o /dev/null -w "%{http_code}" "http://$DASHBOARD_IP:3000/dashboard" 2>/dev/null || echo "000")
    echo "HTTP $HTTP_CODE"
    
    echo -n "Testing /dashboard/journeys : "
    HTTP_CODE=$(docker exec $API curl -s -o /dev/null -w "%{http_code}" "http://$DASHBOARD_IP:3000/dashboard/journeys" 2>/dev/null || echo "000")
    echo "HTTP $HTTP_CODE"
fi

echo ""
echo "Step 7: Testing external access..."
echo "-----------------------------------"

echo -n "Dashboard (https://communication-dashboard.caramelme.com): "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://communication-dashboard.caramelme.com" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "307" ]; then
    echo "✅ HTTP $HTTP_CODE"
else
    echo "⚠️  HTTP $HTTP_CODE"
fi

echo ""
echo "======================================"
echo "Quick Fix Applied!"
echo "======================================"
echo ""
echo "The Next.js configuration has been updated in the running container."
echo ""
echo "NOTE: This is a temporary fix. The change will be lost if:"
echo "  - The container is recreated"
echo "  - Coolify redeploys the service"
echo ""
echo "For a permanent fix:"
echo "  1. Pull the latest code with the fix"
echo "  2. Rebuild the dashboard image"
echo "  3. Update the image in Coolify"
echo ""
echo "Test the dashboard at:"
echo "https://communication-dashboard.caramelme.com"