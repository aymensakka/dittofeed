#!/bin/bash

# ==============================================================================
# Bootstrap Script for Standard Multi-Tenant Deployment
# For use with docker-compose.coolify.yaml and registry images
# ==============================================================================

set -e

echo "=================================================="
echo "🚀 Standard Multi-Tenant Bootstrap"
echo "=================================================="
echo ""

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

# Step 1: Get container IDs
log_step "1/6: Finding containers..."
POSTGRES_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.ID}}" | head -1)
API_CONTAINER=$(docker ps --filter "name=api" --format "{{.ID}}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --filter "name=dashboard" --format "{{.ID}}" | head -1)

if [ -z "$POSTGRES_CONTAINER" ]; then
    log_error "PostgreSQL container not found"
    exit 1
fi

if [ -z "$API_CONTAINER" ]; then
    log_error "API container not found"
    exit 1
fi

log_info "✓ Found PostgreSQL: $POSTGRES_CONTAINER"
log_info "✓ Found API: $API_CONTAINER"
[ ! -z "$DASHBOARD_CONTAINER" ] && log_info "✓ Found Dashboard: $DASHBOARD_CONTAINER"

# Step 2: Wait for PostgreSQL to be ready
log_step "2/6: Waiting for PostgreSQL..."
for i in {1..30}; do
    if docker exec $POSTGRES_CONTAINER pg_isready -U dittofeed > /dev/null 2>&1; then
        log_info "✓ PostgreSQL is ready"
        break
    fi
    echo -n "."
    sleep 2
done

# Step 3: Run database migrations using Drizzle
log_step "3/6: Running database migrations..."
log_info "Attempting Drizzle migrations..."

docker exec -t $API_CONTAINER sh -c "cd /service && npx drizzle-kit push:pg --config=packages/backend-lib/drizzle.config.ts" 2>/dev/null || {
    log_warning "Drizzle migration failed, retrying in 10 seconds..."
    sleep 10
    docker exec -t $API_CONTAINER sh -c "cd /service && npx drizzle-kit push:pg --config=packages/backend-lib/drizzle.config.ts" || {
        log_warning "Drizzle migrations failed. Will apply manual schema..."
        
        # Fallback to manual schema application
        log_info "Applying manual schema..."
        
        # Download the init-database.sh script
        curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/multi-tenant-main/deployment/init-database.sh -o /tmp/init-database.sh
        chmod +x /tmp/init-database.sh
        
        # Run it (it will detect containers and apply schema)
        /tmp/init-database.sh
    }
}

# Step 4: Create initial workspace if needed
log_step "4/6: Checking workspace configuration..."

# Check if workspace exists
WORKSPACE_EXISTS=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM \"Workspace\";" 2>/dev/null || echo "0")

if [ "$WORKSPACE_EXISTS" = "0" ] || [ -z "$WORKSPACE_EXISTS" ]; then
    log_warning "No workspace found, creating initial workspace..."
    
    # Get workspace name from environment or use default
    WORKSPACE_NAME=${BOOTSTRAP_WORKSPACE_NAME:-"default"}
    ADMIN_EMAIL=${BOOTSTRAP_WORKSPACE_ADMIN_EMAIL:-"admin@example.com"}
    
    # Create workspace via SQL
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed <<EOF
INSERT INTO "Workspace" (id, name, type, status, domain, "createdAt", "updatedAt")
VALUES (
    gen_random_uuid(),
    '$WORKSPACE_NAME',
    'Root',
    'Active',
    '$WORKSPACE_NAME',
    NOW(),
    NOW()
) ON CONFLICT (name) DO NOTHING;
EOF
    
    log_info "✓ Workspace created: $WORKSPACE_NAME"
else
    log_info "✓ Workspace already exists"
fi

# Step 5: Setup OAuth provider if configured
log_step "5/6: Configuring OAuth..."

if [ ! -z "$GOOGLE_CLIENT_ID" ] && [ "$GOOGLE_CLIENT_ID" != "your-google-client-id" ]; then
    log_info "Setting up Google OAuth provider..."
    
    # Get workspace ID
    WORKSPACE_ID=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT id FROM \"Workspace\" LIMIT 1;" | xargs)
    
    if [ ! -z "$WORKSPACE_ID" ]; then
        docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed <<EOF
INSERT INTO "AuthProvider" ("workspaceId", "type", "enabled", "config", "createdAt", "updatedAt")
VALUES (
    '$WORKSPACE_ID'::uuid,
    'google',
    true,
    '{"provider": "google", "scope": ["openid", "email", "profile"]}'::jsonb,
    NOW(),
    NOW()
) ON CONFLICT ("workspaceId", "type") DO UPDATE
SET enabled = true,
    config = EXCLUDED.config,
    "updatedAt" = NOW();
EOF
        log_info "✓ Google OAuth configured"
    fi
else
    log_warning "Google OAuth not configured (missing GOOGLE_CLIENT_ID)"
fi

# Step 6: Update Cloudflare tunnel if configured
log_step "6/6: Updating network configuration..."

if [ ! -z "$CF_TUNNEL_TOKEN" ]; then
    log_info "Updating Cloudflare tunnel configuration..."
    
    CLOUDFLARED_CONTAINER=$(docker ps --filter "name=cloudflared" --format "{{.ID}}" | head -1)
    
    if [ ! -z "$CLOUDFLARED_CONTAINER" ]; then
        # Get container IPs
        API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER | head -1)
        DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER | head -1)
        
        log_info "API IP: $API_IP"
        log_info "Dashboard IP: $DASHBOARD_IP"
        
        # Update tunnel configuration
        docker exec $CLOUDFLARED_CONTAINER sh -c "
            cat > /etc/cloudflared/config.yml <<EOL
tunnel: ${CF_TUNNEL_ID}
credentials-file: /etc/cloudflared/tunnel.json

ingress:
  - hostname: communication-api.caramelme.com
    service: http://${API_IP}:3001
  - hostname: communication-dashboard.caramelme.com
    service: http://${DASHBOARD_IP}:3000
  - service: http_status:404
EOL
        " || log_warning "Failed to update Cloudflare config"
        
        # Restart cloudflared
        docker restart $CLOUDFLARED_CONTAINER || log_warning "Failed to restart cloudflared"
        log_info "✓ Cloudflare tunnel updated"
    else
        log_warning "Cloudflared container not found"
    fi
else
    log_info "Cloudflare tunnel not configured (no CF_TUNNEL_TOKEN)"
fi

# Final checks
echo ""
echo "=================================================="
log_info "✨ Standard Multi-Tenant Bootstrap Complete!"
echo "=================================================="
echo ""

# Test services
log_info "Testing services..."
echo -n "  API Health: "
docker exec $API_CONTAINER curl -s http://localhost:3001/health >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed"

echo -n "  Dashboard: "
docker exec $DASHBOARD_CONTAINER curl -s http://localhost:3000/dashboard >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed"

# Show workspace info
echo ""
log_info "Workspace Information:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT name, type, status, domain FROM \"Workspace\";"

echo ""
log_info "Next steps:"
echo "  1. Access dashboard at: ${DASHBOARD_URL:-https://your-domain.com/dashboard}"
echo "  2. Sign in with Google OAuth"
echo "  3. Monitor logs: docker logs -f $API_CONTAINER"
echo ""
echo "=================================================="