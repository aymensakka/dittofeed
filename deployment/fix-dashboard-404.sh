#!/bin/bash

echo "======================================"
echo "Fixing Dashboard 404 Issue"
echo "======================================"
echo ""

# This script addresses the 404 issue by:
# 1. Verifying environment variables
# 2. Checking workspace configuration
# 3. Rebuilding if necessary

DASHBOARD=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*p0gcsc088cogco0cokco4404" | head -1)
API=$(docker ps --format '{{.Names}}' | grep -E "api.*p0gcsc088cogco0cokco4404" | head -1)
POSTGRES=$(docker ps -q -f name=postgres | head -1)

if [ -z "$DASHBOARD" ]; then
    echo "❌ Dashboard container not found"
    exit 1
fi

echo "Step 1: Checking current configuration..."
echo "----------------------------------------"

# Get current auth mode
CURRENT_AUTH_MODE=$(docker exec $DASHBOARD env | grep "^NEXT_PUBLIC_AUTH_MODE=" | cut -d= -f2)
echo "Current NEXT_PUBLIC_AUTH_MODE: $CURRENT_AUTH_MODE"

if [ "$CURRENT_AUTH_MODE" != "multi-tenant" ]; then
    echo "❌ ISSUE FOUND: NEXT_PUBLIC_AUTH_MODE is not 'multi-tenant'"
    echo ""
    echo "ACTION REQUIRED:"
    echo "----------------"
    echo "1. Go to Coolify dashboard"
    echo "2. Navigate to the Dashboard service environment variables"
    echo "3. Update: NEXT_PUBLIC_AUTH_MODE=multi-tenant"
    echo "4. Redeploy the Dashboard service"
    echo ""
    echo "After redeployment, run this script again."
    exit 1
fi

echo "✅ Auth mode is correctly set to multi-tenant"
echo ""

echo "Step 2: Verifying workspace configuration..."
echo "--------------------------------------------"

# Get workspace from env and DB
WORKSPACE_NAME=$(docker exec $DASHBOARD env | grep "BOOTSTRAP_WORKSPACE_NAME" | cut -d= -f2)
DB_WORKSPACE=$(docker exec $POSTGRES psql -U dittofeed -d dittofeed -t -c "SELECT name FROM \"Workspace\" LIMIT 1;" 2>/dev/null | tr -d ' \n')

echo "Environment workspace: $WORKSPACE_NAME"
echo "Database workspace: $DB_WORKSPACE"

if [ "$WORKSPACE_NAME" != "$DB_WORKSPACE" ]; then
    echo "❌ Workspace name mismatch detected"
    echo "Updating database to match environment..."
    
    docker exec $POSTGRES psql -U dittofeed -d dittofeed -c "UPDATE \"Workspace\" SET name = '$WORKSPACE_NAME', \"updatedAt\" = NOW() WHERE name = '$DB_WORKSPACE';" 2>/dev/null
    
    echo "✅ Workspace updated to: $WORKSPACE_NAME"
    echo "Restarting services..."
    
    docker restart $DASHBOARD > /dev/null 2>&1
    docker restart $API > /dev/null 2>&1
    
    echo "Waiting for services to start..."
    sleep 15
else
    echo "✅ Workspace names match"
fi

echo ""
echo "Step 3: Testing dashboard routes..."
echo "-----------------------------------"

# Get IPs
DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD 2>/dev/null | head -c -1)
API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API 2>/dev/null | head -c -1)

echo "Dashboard IP: $DASHBOARD_IP"
echo "API IP: $API_IP"
echo ""

# Test internal routes
echo -n "Testing root (/) : "
HTTP_CODE=$(docker exec $API curl -s -o /dev/null -w "%{http_code}" "http://$DASHBOARD_IP:3000/" 2>/dev/null || echo "000")
echo "HTTP $HTTP_CODE"

echo -n "Testing /dashboard : "
HTTP_CODE=$(docker exec $API curl -s -o /dev/null -w "%{http_code}" "http://$DASHBOARD_IP:3000/dashboard" 2>/dev/null || echo "000")
echo "HTTP $HTTP_CODE"

echo -n "Testing /dashboard/journeys : "
HTTP_CODE=$(docker exec $API curl -s -o /dev/null -w "%{http_code}" "http://$DASHBOARD_IP:3000/dashboard/journeys" 2>/dev/null || echo "000")
echo "HTTP $HTTP_CODE"

echo ""
echo "Step 4: Checking external access..."
echo "-----------------------------------"

echo -n "Dashboard (https://communication-dashboard.caramelme.com): "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://communication-dashboard.caramelme.com" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "307" ]; then
    echo "✅ HTTP $HTTP_CODE"
else
    echo "❌ HTTP $HTTP_CODE"
fi

echo -n "API (https://communication-api.caramelme.com/health): "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://communication-api.caramelme.com/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ HTTP $HTTP_CODE"
else
    echo "❌ HTTP $HTTP_CODE"
fi

echo ""
echo "Step 5: Dashboard logs (last 10 relevant lines)..."
echo "-------------------------------------------------"
docker logs $DASHBOARD --tail 30 2>&1 | grep -v "Compiled\|wait\|Building" | tail -10

echo ""
echo "======================================"
echo "Troubleshooting Summary:"
echo "======================================"

if [ "$HTTP_CODE" = "404" ]; then
    echo ""
    echo "The 404 issue persists. This is likely due to:"
    echo ""
    echo "1. Next.js redirect configuration conflict"
    echo "   - The next.config.js has conflicting redirects"
    echo "   - Need to rebuild the dashboard image with fixed config"
    echo ""
    echo "2. Authentication requirement not met"
    echo "   - Multi-tenant mode requires authentication"
    echo "   - Check if /api/auth/session is accessible"
    echo ""
    echo "RECOMMENDED ACTIONS:"
    echo "-------------------"
    echo "1. Check if the dashboard was built with the correct environment:"
    echo "   docker exec $DASHBOARD cat /app/.next/BUILD_ID"
    echo ""
    echo "2. Verify Next.js server is running:"
    echo "   docker exec $DASHBOARD ps aux | grep node"
    echo ""
    echo "3. Check for authentication providers:"
    echo "   docker exec $DASHBOARD env | grep -i oauth"
    echo ""
    echo "4. Consider rebuilding the dashboard image with updated next.config.js"
else
    echo "✅ Dashboard appears to be working!"
    echo ""
    echo "Access your application at:"
    echo "https://communication-dashboard.caramelme.com"
fi