#!/bin/bash

echo "Applying immediate fix to dashboard..."

# Show all containers first
echo "Looking for dashboard container..."
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -i dashboard

# Get dashboard container - try multiple patterns
DASHBOARD=$(docker ps --format '{{.Names}}' | grep -i dashboard | head -1)

if [ -z "$DASHBOARD" ]; then
    # Try another pattern
    DASHBOARD=$(docker ps --format '{{.Names}}' | grep -E ".*dashboard.*" | head -1)
fi

if [ -z "$DASHBOARD" ]; then
    echo "Dashboard container not found. Available containers:"
    docker ps --format 'table {{.Names}}\t{{.Image}}'
    exit 1
fi

echo "Found: $DASHBOARD"

# Create fixed config
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

# Copy to container
docker cp /tmp/next.config.js ${DASHBOARD}:/app/packages/dashboard/next.config.js

# Also try the root next.config.js location
docker cp /tmp/next.config.js ${DASHBOARD}:/app/next.config.js 2>/dev/null

# Restart container
docker restart $DASHBOARD

echo "Fix applied! Wait 30 seconds then try: https://communication-dashboard.caramelme.com"