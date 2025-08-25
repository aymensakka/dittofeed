#!/bin/bash

# Deploy Dittofeed Multi-tenant with Embedded Dashboard for Coolify
# This script uses local Docker images tagged as embedded-final

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions for colored output
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

echo "🚀 Dittofeed Multi-tenant Embedded Dashboard Deployment for Coolify"
echo "=================================================================="
echo ""

# Step 1: Check environment configuration
log_step "1/6: Checking environment configuration..."
# In Coolify, environment variables are already set in the container environment
# We don't need to load from .env file
if [ ! -z "$JWT_SECRET" ]; then
    log_info "✓ Environment variables loaded from Coolify"
else
    log_warning "Environment variables not found, checking for .env file..."
    if [ -f .env ]; then
        log_info "Loading from .env file..."
        export $(cat .env | grep -v '^#' | xargs)
    else
        log_error "No environment variables found! Please configure in Coolify UI."
        exit 1
    fi
fi

# Step 2: Verify required environment variables
log_step "2/6: Verifying required configuration..."
missing_vars=()

if [ -z "$JWT_SECRET" ]; then
    missing_vars+=("JWT_SECRET")
fi

if [ -z "$GOOGLE_CLIENT_ID" ]; then
    missing_vars+=("GOOGLE_CLIENT_ID")
fi

if [ -z "$GOOGLE_CLIENT_SECRET" ]; then
    missing_vars+=("GOOGLE_CLIENT_SECRET")
fi

if [ ${#missing_vars[@]} -gt 0 ]; then
    log_error "Missing required environment variables:"
    for var in "${missing_vars[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "Please configure these in Coolify UI under Environment Variables"
    exit 1
fi

log_info "✓ Configuration verified"

# Step 3: Check if Docker images exist locally
log_step "3/6: Checking Docker images..."
images_missing=false

for image in "aymensakka/dittofeed-api:embedded-final" \
             "aymensakka/dittofeed-dashboard:embedded-final" \
             "aymensakka/dittofeed-worker:embedded-final"; do
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${image}$"; then
        log_info "✓ Found: $image"
    else
        log_error "✗ Missing: $image"
        images_missing=true
    fi
done

if [ "$images_missing" = true ]; then
    log_error "Some Docker images are missing. Please build them first:"
    echo ""
    echo "cd /root/dittofeed"
    echo "docker build --platform linux/amd64 -f packages/api/Dockerfile -t aymensakka/dittofeed-api:embedded-final ."
    echo "docker build --platform linux/amd64 -f packages/dashboard/Dockerfile -t aymensakka/dittofeed-dashboard:embedded-final ."
    echo "docker build --platform linux/amd64 -f packages/worker/Dockerfile -t aymensakka/dittofeed-worker:embedded-final ."
    exit 1
fi

# Step 4: Stop any existing Coolify containers
log_step "4/6: Stopping existing containers..."
if docker ps | grep -q "p0gcsc088cogco0cokco4404"; then
    log_warning "Stopping Coolify containers..."
    docker stop $(docker ps -q --filter name=p0gcsc088cogco0cokco4404) || true
    sleep 2
fi

# Stop any existing deployment
if [ -f docker-compose.coolify-embedded.yaml ]; then
    docker compose -f docker-compose.coolify-embedded.yaml down || true
fi

# Step 5: Start services
log_step "5/6: Starting services..."
docker compose -f docker-compose.coolify-embedded.yaml up -d

# Wait for services to be ready
log_info "Waiting for services to start..."
sleep 15

# Check service status
docker compose -f docker-compose.coolify-embedded.yaml ps

# Step 6: Run database migrations
log_step "6/6: Running database migrations..."
log_info "Waiting for API to be ready..."
sleep 10

# Run migrations
docker compose -f docker-compose.coolify-embedded.yaml exec -T api npx drizzle-kit push:pg --config=drizzle.config.ts 2>/dev/null || {
    log_warning "Initial migration attempt failed, retrying in 10 seconds..."
    sleep 10
    docker compose -f docker-compose.coolify-embedded.yaml exec -T api npx drizzle-kit push:pg --config=drizzle.config.ts || {
        log_warning "Migrations might have already been applied or will apply on first API request"
    }
}

echo ""
echo "===================================================================="
log_info "✨ Deployment complete!"
echo ""
echo "📍 Services are running at:"
echo "   Dashboard: http://${NEXTAUTH_URL:-localhost:3000}"
echo "   API: http://${NEXT_PUBLIC_API_BASE:-localhost:3001}"
echo ""
echo "📊 Monitor services:"
echo "   docker compose -f docker-compose.coolify-embedded.yaml ps"
echo ""
echo "📋 View logs:"
echo "   docker compose -f docker-compose.coolify-embedded.yaml logs -f api"
echo "   docker compose -f docker-compose.coolify-embedded.yaml logs -f dashboard"
echo "   docker compose -f docker-compose.coolify-embedded.yaml logs -f worker"
echo ""
echo "🔄 Restart services:"
echo "   docker compose -f docker-compose.coolify-embedded.yaml restart"
echo ""
echo "🛑 Stop services:"
echo "   docker compose -f docker-compose.coolify-embedded.yaml down"
echo ""
echo "===================================================================="