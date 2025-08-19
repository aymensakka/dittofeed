#!/bin/bash

echo "======================================"
echo "Applying Dashboard 404 Fix"
echo "======================================"
echo ""
echo "This script fixes the Next.js configuration issue causing 404 errors"
echo ""

# Check if we're in the right directory
if [ ! -f "packages/dashboard/next.config.js" ]; then
    echo "❌ Error: Must run from dittofeed-multitenant root directory"
    exit 1
fi

echo "Step 1: Backing up original next.config.js..."
cp packages/dashboard/next.config.js packages/dashboard/next.config.js.backup
echo "✅ Backup created: packages/dashboard/next.config.js.backup"
echo ""

echo "Step 2: Applying fixed configuration..."
cat > packages/dashboard/next.config.js << 'EOF'
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

echo "✅ Fixed configuration applied"
echo ""

echo "Step 3: Showing the change..."
echo "-------------------------------"
echo "The conflicting redirect with 'basePath: false' has been removed."
echo ""

echo "Step 4: Next steps..."
echo "---------------------"
echo ""
echo "Option A: Quick fix (restart existing container):"
echo "  1. Copy this fixed config to the server"
echo "  2. docker cp next.config.js <dashboard-container>:/app/packages/dashboard/"
echo "  3. docker restart <dashboard-container>"
echo ""
echo "Option B: Proper fix (rebuild image):"
echo "  1. Commit this change: git add -A && git commit -m 'fix: remove conflicting redirect in next.config.js'"
echo "  2. Push to repository: git push"
echo "  3. Rebuild dashboard image: ./deployment/build-dashboard.sh"
echo "  4. Redeploy in Coolify"
echo ""
echo "Option C: Test locally first:"
echo "  1. cd packages/dashboard"
echo "  2. yarn build"
echo "  3. yarn start"
echo "  4. Test at http://localhost:3000/dashboard"
echo ""
echo "======================================"
echo "Fix Applied Successfully!"
echo "======================================"