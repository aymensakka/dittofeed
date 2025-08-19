#!/bin/bash

# ==============================================================================
# Build Dashboard with Multi-tenant Auth Mode - Docker Only
# This script builds the dashboard image directly with Docker
# ==============================================================================

set -e

echo "===================================================="
echo "Building Dashboard with Multi-tenant Auth Mode"
echo "===================================================="
echo ""

# Registry and image settings
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo/dittofeed"
TAG="multitenancy-oauth-v1"
IMAGE="${REGISTRY}/${REPO}/dashboard:${TAG}"

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    echo "❌ Error: package.json not found. Please run from the dittofeed root directory."
    exit 1
fi

echo "Step 1: Creating custom Dockerfile with auth mode..."
echo "-----------------------------------------------------"
cat > packages/dashboard/Dockerfile.multitenant << 'EOF'
# use buster in the build step, lite in the production step
FROM node:20-slim AS builder

# Accept the build argument in the builder stage
ARG APP_VERSION

WORKDIR /app

RUN apt-get update -y && \
    apt-get install -y openssl && \
    apt-get install -y curl

COPY . .

RUN yarn set version 4.1.1

# Set environment variables for the build
ENV NODE_ENV=production
ENV AUTH_MODE=multi-tenant
ENV NEXT_PUBLIC_AUTH_MODE=multi-tenant
ENV NEXT_PUBLIC_ENABLE_MULTITENANCY=true

RUN yarn workspaces focus isomorphic-lib emailo backend-lib dashboard

RUN mkdir -p packages/dashboard/public/public && \
    curl https://raw.githubusercontent.com/dittofeed/sdk-web/7050a5b6f85fe0f9cab59043b782b65c9a911791/snippet/dittofeed.umd.js -o packages/dashboard/public/public/dittofeed.umd.js && \
    curl https://raw.githubusercontent.com/dittofeed/sdk-web/7050a5b6f85fe0f9cab59043b782b65c9a911791/snippet/dittofeed.es.js -o packages/dashboard/public/public/dittofeed.es.js

RUN yarn workspace emailo build && \
    yarn workspace isomorphic-lib build && \
    yarn workspace backend-lib build && \
    yarn workspace dashboard build

# Production image, copy all the files and run next
FROM node:20-slim AS runner

# Redefine the ARG in the production stage
ARG APP_VERSION

WORKDIR /app

RUN yarn set version 4.1.1

RUN apt-get update -y && \
    apt-get install -y openssl

ENV NODE_ENV=production
ENV AUTH_MODE=multi-tenant
ENV NEXT_PUBLIC_AUTH_MODE=multi-tenant
ENV NEXT_PUBLIC_ENABLE_MULTITENANCY=true

# Set the environment variable
ENV APP_VERSION=${APP_VERSION}

# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder /app/packages/dashboard/.next/standalone/packages/dashboard ./
COPY --from=builder /app/packages/dashboard/.next/standalone/node_modules ./node_modules
# static and public should be on CDN
COPY --from=builder /app/packages/dashboard/.next/static ./.next/static
COPY --from=builder /app/packages/dashboard/public ./public
COPY --from=builder /app/.yarn ./.yarn
COPY --from=builder /app/*.json /app/yarn.lock /app/.yarnrc.yml ./

EXPOSE 3000

CMD ["node", "server.js"]
EOF

echo "✅ Custom Dockerfile created"
echo ""

echo "Step 2: Building dashboard Docker image..."
echo "-------------------------------------------"
echo "This will take 10-15 minutes..."
echo ""
docker build \
    --platform linux/amd64 \
    -f packages/dashboard/Dockerfile.multitenant \
    -t "$IMAGE" \
    --progress=plain \
    . || {
    echo "❌ Failed to build Docker image"
    exit 1
}
echo "✅ Dashboard image built: $IMAGE"
echo ""

echo "Step 3: Logging into Docker registry..."
echo "----------------------------------------"
docker login "$REGISTRY" --username coolify-system --password '9sFPGGDJUFnE4z*z4Aj9' || {
    echo "❌ Failed to login to registry"
    exit 1
}
echo "✅ Logged into Docker registry"
echo ""

echo "Step 4: Pushing image to registry..."
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
echo "1. In Coolify, update the dashboard image to:"
echo "   $IMAGE"
echo ""
echo "2. Ensure these environment variables are set in Coolify:"
echo "   AUTH_MODE=multi-tenant"
echo "   GOOGLE_CLIENT_ID=(your-google-client-id)"
echo "   GOOGLE_CLIENT_SECRET=(your-google-client-secret)"
echo "   NEXTAUTH_URL=https://communication-dashboard.caramelme.com/dashboard"
echo "   NEXTAUTH_SECRET=(your-nextauth-secret)"
echo ""
echo "3. Redeploy the dashboard service in Coolify"
echo ""
echo "The image now has multi-tenant auth mode baked in at build time."
echo ""