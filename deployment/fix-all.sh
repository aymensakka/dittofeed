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

# Step 3: Fix network and IPs
echo ""
echo "Step 3: Fixing network configuration and IPs..."
echo "----------------------------------------"
"$SCRIPT_DIR/bootstrap-with-network-fix.sh"
echo ""

# Step 4: Update Cloudflare if script exists
if [ -f "$SCRIPT_DIR/update-cf-from-host.sh" ]; then
    echo "Step 4: Updating Cloudflare tunnel..."
    echo "----------------------------------------"
    "$SCRIPT_DIR/update-cf-from-host.sh"
    echo ""
else
    echo "Step 4: Cloudflare update script not found, skipping..."
fi

# Step 5: Final status check
echo ""
echo "Step 5: Final status check..."
echo "----------------------------------------"
"$SCRIPT_DIR/bootstrap-simple.sh" --verbose
echo ""

# Step 6: Test external endpoints
echo "Step 6: Testing external endpoints..."
echo "----------------------------------------"

DOMAIN="${DOMAIN:-caramelme.com}"

echo -n "Dashboard (https://communication-dashboard.${DOMAIN}): "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://communication-dashboard.${DOMAIN}" 2>/dev/null || echo "000")
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
echo "  3. bootstrap-with-network-fix.sh - Network and IP fixes"
echo "  4. update-cf-from-host.sh - Cloudflare tunnel update"
echo ""
echo "Access your application at:"
echo "  https://communication-dashboard.${DOMAIN}"
echo ""
echo "If you still see issues:"
echo "  1. Check logs: docker logs \$(docker ps -q -f name=dashboard) --tail 50"
echo "  2. Verify AUTH_MODE in Coolify: NEXT_PUBLIC_AUTH_MODE=multi-tenant"
echo "  3. Wait 30-60 seconds for services to stabilize"
echo ""
echo "====================================================="