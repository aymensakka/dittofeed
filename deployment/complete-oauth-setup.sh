#!/bin/bash

# ==============================================================================
# Complete OAuth Setup - Final Fix
# ==============================================================================

set -e

echo "===================================================="
echo "Completing OAuth Setup"
echo "===================================================="
echo ""

PROJECT_ID="p0gcsc088cogco0cokco4404"
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "❌ PostgreSQL container not found"
    exit 1
fi

echo "PostgreSQL container: $POSTGRES_CONTAINER"
echo ""

# Step 1: Add updatedAt column properly
echo "Step 1: Adding updatedAt column..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "ALTER TABLE \"AuthProvider\" ADD COLUMN \"updatedAt\" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL;" 2>&1 || {
    echo "Column might already exist or error occurred"
}
echo ""

# Step 2: Update existing row
echo "Step 2: Updating existing OAuth provider..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "UPDATE \"AuthProvider\" SET \"updatedAt\" = NOW() WHERE \"updatedAt\" IS NULL;" 2>&1 || true
echo ""

# Step 3: Create unique index
echo "Step 3: Creating unique index..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "CREATE UNIQUE INDEX IF NOT EXISTS \"AuthProvider_workspaceId_type_key\" ON \"AuthProvider\"(\"workspaceId\", type);" 2>&1
echo ""

# Step 4: Verify final state
echo "Step 4: Final verification..."
echo "AuthProvider entries:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "SELECT type, enabled, config FROM \"AuthProvider\";" 2>&1
echo ""

echo "Table structure:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\d \"AuthProvider\"" 2>&1
echo ""

# Step 5: Check environment variables
echo "Step 5: Checking OAuth environment variables..."
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
if [ ! -z "$DASHBOARD_CONTAINER" ]; then
    echo "Dashboard OAuth configuration:"
    docker exec $DASHBOARD_CONTAINER env | grep -E "AUTH_MODE|GOOGLE|NEXTAUTH" | sort
fi
echo ""

# Step 6: Restart services
echo "Step 6: Restarting all services..."
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
WORKER_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "worker.*${PROJECT_ID}" | head -1)

[ ! -z "$API_CONTAINER" ] && docker restart $API_CONTAINER > /dev/null 2>&1 && echo "✅ API restarted"
[ ! -z "$DASHBOARD_CONTAINER" ] && docker restart $DASHBOARD_CONTAINER > /dev/null 2>&1 && echo "✅ Dashboard restarted"
[ ! -z "$WORKER_CONTAINER" ] && docker restart $WORKER_CONTAINER > /dev/null 2>&1 && echo "✅ Worker restarted"

echo ""
echo "⏳ Waiting 30 seconds for services to fully start..."
sleep 30

# Step 7: Check API health and logs
echo ""
echo "Step 7: Checking service health..."
if [ ! -z "$API_CONTAINER" ]; then
    echo "API Container Status:"
    docker ps | grep $API_CONTAINER | awk '{print $1, $7, $8, $9, $10}'
    echo ""
    
    echo -n "API internal health check: "
    docker exec $API_CONTAINER curl -s -f http://localhost:3001/health >/dev/null 2>&1 && echo "✅ Healthy" || {
        echo "❌ Not healthy"
        echo ""
        echo "=== API ERROR LOGS ==="
        docker logs $API_CONTAINER --tail 50 2>&1 | grep -i "error\|fail\|exception\|critical" || echo "No obvious errors in recent logs"
        echo ""
        echo "=== LAST 30 LINES OF API LOGS ==="
        docker logs $API_CONTAINER --tail 30 2>&1
    }
fi
echo ""

# Step 8: Test external endpoints
echo "Step 8: Testing external endpoints..."
echo -n "API endpoint: "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://communication-api.caramelme.com/health 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ https://communication-api.caramelme.com/health - HTTP 200"
else
    echo "❌ https://communication-api.caramelme.com/health - HTTP $HTTP_CODE"
    echo ""
    echo "Checking Cloudflare tunnel..."
    CLOUDFLARED=$(docker ps --format '{{.Names}}' | grep cloudflared | head -1)
    if [ ! -z "$CLOUDFLARED" ]; then
        echo "Cloudflared container: $CLOUDFLARED"
        docker logs $CLOUDFLARED --tail 10 2>&1 | grep -i "error\|fail" || echo "No errors in cloudflared logs"
    fi
fi

echo -n "Dashboard endpoint: "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://communication-dashboard.caramelme.com/dashboard 2>/dev/null)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "307" ]; then
    echo "✅ https://communication-dashboard.caramelme.com/dashboard - HTTP $HTTP_CODE"
else
    echo "❌ https://communication-dashboard.caramelme.com/dashboard - HTTP $HTTP_CODE"
fi

echo ""
echo "===================================================="
echo "OAuth Setup Status"
echo "===================================================="
echo ""

# Final summary
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "307" ]; then
    echo "✅ OAuth setup appears complete!"
    echo ""
    echo "Visit: https://communication-dashboard.caramelme.com/dashboard"
    echo ""
    echo "You should see:"
    echo "  - Google sign-in button"
    echo "  - NOT 'anonymous@email.com'"
    echo ""
    echo "If you still see anonymous mode, the dashboard image needs rebuilding with:"
    echo "  ./deployment/build-dashboard-multitenant.sh"
else
    echo "⚠️  Services may still be starting or there's an issue"
    echo ""
    echo "Debug commands:"
    echo "  docker logs $API_CONTAINER --tail 100"
    echo "  docker logs $DASHBOARD_CONTAINER --tail 100"
    echo ""
    echo "To check if it's an image issue:"
    echo "  docker exec $DASHBOARD_CONTAINER env | grep AUTH_MODE"
fi
echo "===================================================="