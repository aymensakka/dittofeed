#!/bin/bash

# ==============================================================================
# Deploy Embedded Dashboard to Production Server
# ==============================================================================

set -e

echo "=================================================="
echo "🚀 Deploying Embedded Dashboard to Server"
echo "=================================================="
echo ""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Step 1: Clone repository if not exists
log_step "1/7: Setting up repository..."
if [ ! -d "/root/dittofeed" ]; then
    log_info "Cloning repository..."
    cd /root
    git clone https://github.com/aymensakka/dittofeed.git
    cd dittofeed
    git checkout multi-tenant-main
else
    log_info "Repository exists, pulling latest..."
    cd /root/dittofeed
    git fetch origin
    git checkout multi-tenant-main
    git pull origin multi-tenant-main
fi

# Step 2: Create .env file if not exists
log_step "2/7: Setting up environment variables..."
if [ ! -f ".env" ]; then
    log_info "Creating .env file..."
    cat > .env <<'EOF'
# Core Configuration
NODE_ENV=production
AUTH_MODE=multi-tenant
AUTH_PROVIDER=google

# Security (generate with: openssl rand -base64 32)
JWT_SECRET=zzy3ZOlTJp3PoQjdPhxCJ9piDAFcIlYnM3nBOmXpGhA=
SECRET_KEY=your-secret-key-for-sessions-change-in-production
NEXTAUTH_SECRET=your-nextauth-secret-change-in-production

# Google OAuth (replace with your credentials)
GOOGLE_CLIENT_ID=your-google-client-id-here
GOOGLE_CLIENT_SECRET=your-google-client-secret-here

# Database
POSTGRES_PASSWORD=securepassword123
DATABASE_URL=postgresql://dittofeed:securepassword123@postgres:5432/dittofeed

# Services
REDIS_PASSWORD=redispassword123
CLICKHOUSE_PASSWORD=clickhousepassword123
CLICKHOUSE_USER=dittofeed

# URLs (adjust for your domain)
NEXTAUTH_URL=https://communication-dashboard.caramelme.com/dashboard
NEXT_PUBLIC_API_BASE=https://communication-api.caramelme.com
API_BASE_URL=https://communication-api.caramelme.com
DASHBOARD_URL=https://communication-dashboard.caramelme.com

# Multi-tenancy
NEXT_PUBLIC_AUTH_MODE=multi-tenant
NEXT_PUBLIC_ENABLE_MULTITENANCY=true
WORKSPACE_ISOLATION_ENABLED=true
ALLOW_AUTO_WORKSPACE_CREATION=true

# Bootstrap
BOOTSTRAP_WORKSPACE_NAME=caramel
BOOTSTRAP_WORKSPACE_ADMIN_EMAIL=admin@caramelme.com

# Embedded Dashboard Features
ENABLE_EMBEDDED_DASHBOARD=true
SESSION_TOKEN_TTL=900
REFRESH_TOKEN_TTL=604800
MAX_SESSIONS_PER_WORKSPACE=1000

# Cloudflare Tunnel (if using)
CF_TUNNEL_TOKEN=
CF_TUNNEL_ID=
EOF
    log_warning "Please update .env file with your actual credentials!"
    log_info "Pausing for 10 seconds to allow review..."
    sleep 10
else
    log_info ".env file exists, loading..."
    source .env
fi

# Step 3: Stop existing containers
log_step "3/7: Stopping existing containers..."
docker-compose -f docker-compose.coolify-embedded.yaml down 2>/dev/null || true
docker-compose -f docker-compose.coolify.yaml down 2>/dev/null || true

# Step 4: Start services with embedded docker-compose
log_step "4/7: Starting embedded services..."
log_info "Using docker-compose.coolify-embedded.yaml..."

docker-compose -f docker-compose.coolify-embedded.yaml up -d

# Wait for services to start
log_info "Waiting for services to start..."
sleep 20

# Step 5: Check container status
log_step "5/7: Checking container status..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"

# Step 6: Run bootstrap script
log_step "6/7: Running embedded bootstrap..."
log_info "Downloading and running bootstrap-embedded-dashboard.sh..."

curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/multi-tenant-main/deployment/bootstrap-embedded-dashboard.sh -o /tmp/bootstrap-embedded-dashboard.sh
chmod +x /tmp/bootstrap-embedded-dashboard.sh
/tmp/bootstrap-embedded-dashboard.sh

# Step 7: Verify deployment
log_step "7/7: Verifying deployment..."

# Check API health
echo -n "API Health: "
curl -s http://localhost:3001/health >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed"

echo -n "Embedded Sessions API: "
curl -s http://localhost:3001/api-l/embedded-sessions/health >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed"

# Check Dashboard
echo -n "Dashboard: "
curl -s http://localhost:3000/dashboard >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed"

echo -n "Embedded Dashboard: "
curl -s http://localhost:3000/dashboard-l/embedded/journeys >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed"

# Show logs
echo ""
log_info "Recent API logs:"
docker logs $(docker ps -q -f name=api) 2>&1 | tail -5

echo ""
echo "=================================================="
log_info "✨ Embedded Dashboard Deployment Complete!"
echo "=================================================="
echo ""

log_info "Next Steps:"
echo "  1. Update Cloudflare tunnel if needed:"
echo "     ./deployment/update-cf-from-host.sh"
echo ""
echo "  2. Access dashboard at:"
echo "     ${DASHBOARD_URL}/dashboard"
echo ""
echo "  3. Test embedded features at:"
echo "     ${DASHBOARD_URL}/dashboard-l/embedded/journeys/v2"
echo ""
echo "  4. Monitor logs:"
echo "     docker logs -f \$(docker ps -q -f name=api)"
echo ""
echo "=================================================="