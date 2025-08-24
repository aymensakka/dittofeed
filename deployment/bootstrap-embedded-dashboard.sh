#!/bin/bash

# ==============================================================================
# Bootstrap Script for Embedded Dashboard Deployment
# For use with docker-compose.coolify-embedded.yaml and embedded-final images
# ==============================================================================

set -e

echo "=================================================="
echo "🚀 Embedded Dashboard Bootstrap"
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

# Step 1: Get container IDs (different naming pattern for embedded deployment)
log_step "1/7: Finding containers..."
POSTGRES_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.ID}}" | head -1)
API_CONTAINER=$(docker ps --filter "name=api" --format "{{.ID}}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --filter "name=dashboard" --format "{{.ID}}" | head -1)
REDIS_CONTAINER=$(docker ps --filter "name=redis" --format "{{.ID}}" | head -1)
CLICKHOUSE_CONTAINER=$(docker ps --filter "name=clickhouse" --format "{{.ID}}" | head -1)

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
[ ! -z "$REDIS_CONTAINER" ] && log_info "✓ Found Redis: $REDIS_CONTAINER"
[ ! -z "$CLICKHOUSE_CONTAINER" ] && log_info "✓ Found ClickHouse: $CLICKHOUSE_CONTAINER"

# Step 2: Wait for all services to be ready
log_step "2/7: Waiting for services..."

# PostgreSQL
for i in {1..30}; do
    if docker exec $POSTGRES_CONTAINER pg_isready -U dittofeed > /dev/null 2>&1; then
        log_info "✓ PostgreSQL is ready"
        break
    fi
    echo -n "."
    sleep 2
done

# Redis
if [ ! -z "$REDIS_CONTAINER" ]; then
    for i in {1..30}; do
        if docker exec $REDIS_CONTAINER redis-cli ping > /dev/null 2>&1; then
            log_info "✓ Redis is ready"
            break
        fi
        echo -n "."
        sleep 2
    done
fi

# Step 3: Run FULL database migrations including embedded session tables
log_step "3/7: Running database migrations with embedded session support..."

# First attempt with Drizzle
docker exec -t $API_CONTAINER sh -c "cd /service && npx drizzle-kit push:pg --config=packages/backend-lib/drizzle.config.ts" 2>/dev/null || {
    log_warning "Drizzle migration failed, applying complete schema manually..."
    
    # Apply the complete schema including embedded sessions
    log_info "Creating embedded session tables..."
    
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed <<'EOF'
-- Embedded Sessions Tables (critical for iframe embedding)
CREATE TABLE IF NOT EXISTS "EmbeddedSession" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "sessionId" TEXT NOT NULL UNIQUE,
    "workspaceId" UUID NOT NULL,
    "refreshToken" TEXT NOT NULL UNIQUE,
    "refreshTokenFamily" UUID NOT NULL,
    "accessTokenHash" TEXT NOT NULL,
    "previousAccessTokenHash" TEXT,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "lastRefreshedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "refreshExpiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "revocationReason" TEXT,
    "metadata" JSONB DEFAULT '{}' NOT NULL,
    "refreshCount" INTEGER DEFAULT 0 NOT NULL,
    "ipAddress" TEXT,
    "userAgent" TEXT,
    "fingerprint" TEXT
);

CREATE TABLE IF NOT EXISTS "EmbeddedSessionAudit" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "sessionId" TEXT NOT NULL,
    "workspaceId" UUID NOT NULL,
    "action" TEXT NOT NULL,
    "timestamp" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "ipAddress" TEXT,
    "userAgent" TEXT,
    "metadata" JSONB DEFAULT '{}' NOT NULL,
    "success" BOOLEAN NOT NULL,
    "failureReason" TEXT
);

CREATE TABLE IF NOT EXISTS "EmbeddedSessionRateLimit" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "key" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "count" INTEGER DEFAULT 0 NOT NULL,
    "windowStart" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "lastRequestAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS "EmbeddedSession_sessionId_idx" ON "EmbeddedSession"("sessionId");
CREATE INDEX IF NOT EXISTS "EmbeddedSession_workspaceId_idx" ON "EmbeddedSession"("workspaceId");
CREATE INDEX IF NOT EXISTS "EmbeddedSession_refreshToken_idx" ON "EmbeddedSession"("refreshToken");
CREATE INDEX IF NOT EXISTS "EmbeddedSession_refreshTokenFamily_idx" ON "EmbeddedSession"("refreshTokenFamily");
CREATE INDEX IF NOT EXISTS "EmbeddedSession_accessTokenHash_idx" ON "EmbeddedSession"("accessTokenHash");
CREATE INDEX IF NOT EXISTS "EmbeddedSession_revokedAt_idx" ON "EmbeddedSession"("revokedAt");
CREATE INDEX IF NOT EXISTS "EmbeddedSession_expiresAt_idx" ON "EmbeddedSession"("expiresAt");

CREATE INDEX IF NOT EXISTS "EmbeddedSessionAudit_sessionId_idx" ON "EmbeddedSessionAudit"("sessionId");
CREATE INDEX IF NOT EXISTS "EmbeddedSessionAudit_workspaceId_idx" ON "EmbeddedSessionAudit"("workspaceId");
CREATE INDEX IF NOT EXISTS "EmbeddedSessionAudit_timestamp_idx" ON "EmbeddedSessionAudit"("timestamp");

CREATE UNIQUE INDEX IF NOT EXISTS "EmbeddedSessionRateLimit_key_type_idx" ON "EmbeddedSessionRateLimit"("key", "type");

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO dittofeed;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO dittofeed;
EOF
    
    log_info "✓ Embedded session tables created"
    
    # Now run the full init-database.sh for remaining schema
    curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/multi-tenant-main/deployment/init-database.sh -o /tmp/init-database.sh
    chmod +x /tmp/init-database.sh
    /tmp/init-database.sh
}

# Step 4: Verify embedded session tables exist
log_step "4/7: Verifying embedded session tables..."

TABLES_CHECK=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "
    SELECT COUNT(*) FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name IN ('EmbeddedSession', 'EmbeddedSessionAudit', 'EmbeddedSessionRateLimit');
")

if [ "$TABLES_CHECK" -ge "3" ]; then
    log_info "✓ All embedded session tables verified"
else
    log_error "Embedded session tables missing! Count: $TABLES_CHECK"
    exit 1
fi

# Step 5: Create workspace with embedded features enabled
log_step "5/7: Creating workspace with embedded features..."

WORKSPACE_EXISTS=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM \"Workspace\";" 2>/dev/null || echo "0")

if [ "$WORKSPACE_EXISTS" = "0" ] || [ -z "$WORKSPACE_EXISTS" ]; then
    log_warning "No workspace found, creating embedded-enabled workspace..."
    
    WORKSPACE_NAME=${BOOTSTRAP_WORKSPACE_NAME:-"embedded"}
    ADMIN_EMAIL=${BOOTSTRAP_WORKSPACE_ADMIN_EMAIL:-"admin@example.com"}
    
    # Create workspace with embedded configuration
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

-- Add workspace configuration for embedded features
INSERT INTO "WorkspaceConfig" (
    "workspaceId",
    "embeddedDashboardEnabled",
    "sessionTokenTTL",
    "refreshTokenTTL",
    "maxSessionsPerWorkspace",
    "createdAt",
    "updatedAt"
)
SELECT 
    id,
    true,
    900,  -- 15 minutes for access token
    604800,  -- 7 days for refresh token
    1000,  -- max concurrent sessions
    NOW(),
    NOW()
FROM "Workspace"
WHERE name = '$WORKSPACE_NAME'
ON CONFLICT DO NOTHING;
EOF
    
    log_info "✓ Embedded-enabled workspace created: $WORKSPACE_NAME"
else
    log_info "✓ Workspace already exists"
fi

# Step 6: Setup OAuth with embedded session support
log_step "6/7: Configuring OAuth with embedded support..."

if [ ! -z "$GOOGLE_CLIENT_ID" ] && [ "$GOOGLE_CLIENT_ID" != "your-google-client-id" ]; then
    log_info "Setting up Google OAuth with embedded session support..."
    
    WORKSPACE_ID=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT id FROM \"Workspace\" LIMIT 1;" | xargs)
    
    if [ ! -z "$WORKSPACE_ID" ]; then
        docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed <<EOF
INSERT INTO "AuthProvider" ("workspaceId", "type", "enabled", "config", "createdAt", "updatedAt")
VALUES (
    '$WORKSPACE_ID'::uuid,
    'google',
    true,
    '{
        "provider": "google",
        "scope": ["openid", "email", "profile"],
        "allowEmbedded": true,
        "sessionManagement": "jwt-refresh"
    }'::jsonb,
    NOW(),
    NOW()
) ON CONFLICT ("workspaceId", "type") DO UPDATE
SET enabled = true,
    config = '{
        "provider": "google",
        "scope": ["openid", "email", "profile"],
        "allowEmbedded": true,
        "sessionManagement": "jwt-refresh"
    }'::jsonb,
    "updatedAt" = NOW();
EOF
        log_info "✓ Google OAuth configured with embedded support"
    fi
else
    log_warning "Google OAuth not configured (missing GOOGLE_CLIENT_ID)"
fi

# Step 7: Test embedded endpoints
log_step "7/7: Testing embedded dashboard endpoints..."

# Wait for API to be fully ready
sleep 5

# Test standard health endpoint
echo -n "  API Health: "
docker exec $API_CONTAINER curl -s http://localhost:3001/health >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed"

# Test embedded session endpoints
echo -n "  Embedded Sessions API: "
docker exec $API_CONTAINER curl -s http://localhost:3001/api-l/embedded-sessions/health >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed"

# Test dashboard embedded pages
echo -n "  Dashboard Standard: "
docker exec $DASHBOARD_CONTAINER curl -s http://localhost:3000/dashboard >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed"

echo -n "  Dashboard Embedded: "
docker exec $DASHBOARD_CONTAINER curl -s http://localhost:3000/dashboard-l/embedded/journeys >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed"

# Final summary
echo ""
echo "=================================================="
log_info "✨ Embedded Dashboard Bootstrap Complete!"
echo "=================================================="
echo ""

# Show configuration summary
log_info "Configuration Summary:"
echo "  • Workspace: ${WORKSPACE_NAME:-embedded}"
echo "  • Auth Mode: multi-tenant"
echo "  • Session Type: JWT with refresh tokens"
echo "  • Access Token TTL: 15 minutes"
echo "  • Refresh Token TTL: 7 days"
echo "  • Embedded Tables: ✅ Created"
echo ""

log_info "Embedded Dashboard URLs:"
echo "  • Journey Builder: ${DASHBOARD_URL}/dashboard-l/embedded/journeys/v2"
echo "  • Broadcast Editor: ${DASHBOARD_URL}/dashboard-l/embedded/broadcasts/v2"
echo "  • Segment Builder: ${DASHBOARD_URL}/dashboard-l/embedded/segments/v1"
echo "  • Email Templates: ${DASHBOARD_URL}/dashboard-l/embedded/templates/email"
echo "  • SMS Templates: ${DASHBOARD_URL}/dashboard-l/embedded/templates/sms"
echo ""

log_info "API Endpoints:"
echo "  • Create Session: POST ${API_BASE_URL}/api-l/embedded-sessions/create"
echo "  • Refresh Token: POST ${API_BASE_URL}/api-l/embedded-sessions/refresh"
echo "  • Revoke Session: POST ${API_BASE_URL}/api-l/embedded-sessions/revoke"
echo ""

log_info "Testing Embedded Dashboard:"
echo "  1. Use the test HTML file: test-embedded-iframe.html"
echo "  2. Create a session token via API"
echo "  3. Embed dashboard in iframe with token"
echo ""

# Show table counts
log_info "Database Status:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "
    SELECT 'Workspaces' as table_name, COUNT(*) as count FROM \"Workspace\"
    UNION ALL
    SELECT 'Embedded Sessions', COUNT(*) FROM \"EmbeddedSession\"
    UNION ALL
    SELECT 'Session Audits', COUNT(*) FROM \"EmbeddedSessionAudit\"
    UNION ALL
    SELECT 'Rate Limits', COUNT(*) FROM \"EmbeddedSessionRateLimit\";
"

echo ""
echo "=================================================="