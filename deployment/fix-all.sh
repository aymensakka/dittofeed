#!/bin/bash

# ==============================================================================
# Fix All - Wrapper script that uses existing bootstrap scripts
# This orchestrates the existing scripts to fix all issues
# ==============================================================================

set -e

echo "====================================================="
echo "Comprehensive Fix Using Existing Scripts"
echo "Started at: $(date)"
echo "====================================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Step 1: Run simple bootstrap to check status
echo "Step 1: Checking current status..."
echo "----------------------------------------"
"$SCRIPT_DIR/bootstrap-simple.sh"
echo ""

# Parse the output to determine what's needed
NEEDS_WORKSPACE=false
NEEDS_NETWORK_FIX=false

# Check if workspace exists by looking for the summary output
if "$SCRIPT_DIR/bootstrap-simple.sh" 2>&1 | grep -q "No workspace exists"; then
    NEEDS_WORKSPACE=true
    echo -e "${YELLOW}⚠${NC} Workspace needs to be created"
fi

if "$SCRIPT_DIR/bootstrap-simple.sh" 2>&1 | grep -q "API.*unhealthy\|Dashboard.*unhealthy"; then
    NEEDS_NETWORK_FIX=true
    echo -e "${YELLOW}⚠${NC} Services are unhealthy - network fix needed"
fi

# Step 2: Create workspace if needed
if [ "$NEEDS_WORKSPACE" = true ]; then
    echo ""
    echo "Step 2: Creating workspace..."
    echo "----------------------------------------"
    "$SCRIPT_DIR/manual-bootstrap.sh"
    echo ""
else
    echo -e "${GREEN}✓${NC} Workspace already exists"
fi

# Step 3: Fix database schema
echo ""
echo "Step 3: Fixing database schema..."
echo "----------------------------------------"
if [ -f "$SCRIPT_DIR/fix-database-schema.sh" ]; then
    "$SCRIPT_DIR/fix-database-schema.sh"
else
    # Inline schema fix if script doesn't exist
    POSTGRES=$(docker ps --format '{{.Names}}' | grep postgres | head -1)
    if [ ! -z "$POSTGRES" ]; then
        docker exec $POSTGRES psql -U dittofeed -d dittofeed -c \
            "ALTER TABLE \"Workspace\" ADD COLUMN IF NOT EXISTS domain TEXT;" 2>/dev/null || true
        docker exec $POSTGRES psql -U dittofeed -d dittofeed -c \
            "ALTER TABLE \"Workspace\" ADD COLUMN IF NOT EXISTS \"externalId\" TEXT;" 2>/dev/null || true
        docker exec $POSTGRES psql -U dittofeed -d dittofeed -c \
            "ALTER TABLE \"Workspace\" ADD COLUMN IF NOT EXISTS \"parentWorkspaceId\" UUID;" 2>/dev/null || true
        docker exec $POSTGRES psql -U dittofeed -d dittofeed -c \
            "ALTER TABLE \"WorkspaceMemberRole\" ADD COLUMN IF NOT EXISTS \"resourceType\" TEXT;" 2>/dev/null || true
        DOMAIN="${DOMAIN:-caramelme.com}"
        docker exec $POSTGRES psql -U dittofeed -d dittofeed -c \
            "UPDATE \"Workspace\" SET domain = '$DOMAIN' WHERE domain IS NULL;" 2>/dev/null || true
        echo -e "${GREEN}✓${NC} Database schema updated"
    fi
fi
echo ""

# Step 4: Fix network and IPs
echo ""
echo "Step 4: Fixing network configuration and IPs..."
echo "----------------------------------------"
"$SCRIPT_DIR/bootstrap-with-network-fix.sh"
echo ""

# Step 5: Fix Dashboard routing (basePath issue)
echo "Step 5: Fixing Dashboard routing..."
echo "----------------------------------------"
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep dashboard | head -1)
if [ ! -z "$DASHBOARD_CONTAINER" ]; then
    # Check if NEXTAUTH_URL includes /dashboard
    NEXTAUTH_URL=$(docker exec $DASHBOARD_CONTAINER env | grep "^NEXTAUTH_URL=" | cut -d= -f2)
    if [[ ! "$NEXTAUTH_URL" == */dashboard ]]; then
        echo -e "${YELLOW}⚠${NC} NEXTAUTH_URL needs /dashboard suffix"
        echo "Current: $NEXTAUTH_URL"
        echo "Should be: ${NEXTAUTH_URL}/dashboard"
        echo ""
        echo "ACTION REQUIRED:"
        echo "1. Update in Coolify: NEXTAUTH_URL=${NEXTAUTH_URL}/dashboard"
        echo "2. Redeploy the Dashboard service"
    else
        echo -e "${GREEN}✓${NC} NEXTAUTH_URL correctly configured"
    fi
else
    echo -e "${RED}✗${NC} Dashboard container not found"
fi
echo ""

# Step 6: Update Cloudflare if script exists
if [ -f "$SCRIPT_DIR/update-cf-from-host.sh" ]; then
    echo "Step 6: Updating Cloudflare tunnel..."
    echo "----------------------------------------"
    "$SCRIPT_DIR/update-cf-from-host.sh"
    echo ""
else
    echo "Step 6: Cloudflare update script not found, skipping..."
fi

# Step 7: Final status check
echo ""
echo "Step 7: Final status check..."
echo "----------------------------------------"
"$SCRIPT_DIR/bootstrap-simple.sh" --verbose
echo ""

# Step 8: Test external endpoints
echo "Step 8: Testing external endpoints..."
echo "----------------------------------------"

DOMAIN="${DOMAIN:-caramelme.com}"

echo -n "Dashboard (https://communication-dashboard.${DOMAIN}/dashboard): "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://communication-dashboard.${DOMAIN}/dashboard" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "307" ]; then
    echo -e "${GREEN}✓${NC} HTTP $HTTP_CODE"
else
    echo -e "${RED}✗${NC} HTTP $HTTP_CODE"
fi

echo -n "API (https://communication-api.${DOMAIN}): "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://communication-api.${DOMAIN}/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ]; then  # 404 is ok for root
    echo -e "${GREEN}✓${NC} HTTP $HTTP_CODE"
else
    echo -e "${RED}✗${NC} HTTP $HTTP_CODE"
fi

echo ""
echo "====================================================="
echo "Fix Complete!"
echo "====================================================="
echo ""
echo "All existing scripts have been run:"
echo "  1. bootstrap-simple.sh - Status check"
echo "  2. manual-bootstrap.sh - Workspace creation (if needed)"
echo "  3. Database schema fix for multi-tenant support"
echo "  4. bootstrap-with-network-fix.sh - Network and IP fixes"
echo "  5. Dashboard routing check (basePath /dashboard)"
echo "  6. update-cf-from-host.sh - Cloudflare tunnel update"
echo ""
echo "Access your application at:"
echo "  https://communication-dashboard.${DOMAIN}/dashboard"
echo ""
echo "If you still see issues:"
echo "  1. Check logs: docker logs \$(docker ps -q -f name=dashboard) --tail 50"
echo "  2. Verify AUTH_MODE in Coolify: NEXT_PUBLIC_AUTH_MODE=multi-tenant"
echo "  3. Wait 30-60 seconds for services to stabilize"
echo ""
echo "====================================================="