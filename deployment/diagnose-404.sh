#!/bin/bash

echo "======================================"
echo "Diagnosing Dashboard 404 Issue"
echo "======================================"
echo ""

# Get container names
DASHBOARD=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*p0gcsc088cogco0cokco4404" | head -1)
API=$(docker ps --format '{{.Names}}' | grep -E "api.*p0gcsc088cogco0cokco4404" | head -1)
POSTGRES=$(docker ps -q -f name=postgres | head -1)

if [ -z "$DASHBOARD" ]; then
    echo "❌ Dashboard container not found"
    exit 1
fi

echo "1. Container Status:"
echo "-------------------"
echo "Dashboard: $DASHBOARD"
echo "API: $API"
echo ""

echo "2. Critical Environment Variables:"
echo "----------------------------------"
docker exec $DASHBOARD env | grep -E "AUTH_MODE|WORKSPACE|API_BASE|BACKEND_URL" | sort
echo ""

echo "3. Workspace in Database:"
echo "-------------------------"
docker exec $POSTGRES psql -U dittofeed -d dittofeed -c "SELECT id, name, type, status FROM \"Workspace\";" 2>/dev/null
echo ""

echo "4. Dashboard Build Info:"
echo "------------------------"
echo "Next.js build directory:"
docker exec $DASHBOARD ls -la /app/.next/server/pages/ 2>&1 | head -10
echo ""

echo "5. Dashboard Process:"
echo "---------------------"
docker exec $DASHBOARD ps aux | grep -E "node|next" | head -5
echo ""

echo "6. Testing Internal Routes:"
echo "---------------------------"
DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD 2>/dev/null | head -c -1)
echo "Dashboard IP: $DASHBOARD_IP"
echo ""

# Test internal routes
echo "Testing http://$DASHBOARD_IP:3000/ :"
docker exec $API curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://$DASHBOARD_IP:3000/" 2>/dev/null || echo "Failed"

echo "Testing http://$DASHBOARD_IP:3000/dashboard :"
docker exec $API curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://$DASHBOARD_IP:3000/dashboard" 2>/dev/null || echo "Failed"

echo "Testing http://$DASHBOARD_IP:3000/dashboard/journeys :"
docker exec $API curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://$DASHBOARD_IP:3000/dashboard/journeys" 2>/dev/null || echo "Failed"

echo ""

echo "7. Recent Dashboard Logs:"
echo "-------------------------"
docker logs $DASHBOARD --tail 20 2>&1 | grep -v "Compiled\|wait\|Building"
echo ""

echo "8. Checking API Connection:"
echo "---------------------------"
API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API 2>/dev/null | head -c -1)
echo "API IP: $API_IP"
docker exec $DASHBOARD curl -s "http://$API_IP:3001/health" 2>&1 || echo "API health check failed"
echo ""

echo "======================================"
echo "Diagnostic Summary:"
echo "======================================"

# Check for common issues
if docker exec $DASHBOARD env | grep -q "NEXT_PUBLIC_AUTH_MODE=single-tenant"; then
    echo "❌ ISSUE: NEXT_PUBLIC_AUTH_MODE is set to single-tenant (should be multi-tenant)"
fi

if docker exec $DASHBOARD env | grep -q "AUTH_MODE=single-tenant"; then
    echo "❌ ISSUE: AUTH_MODE is set to single-tenant (should be multi-tenant)"
fi

WORKSPACE_NAME=$(docker exec $DASHBOARD env | grep "BOOTSTRAP_WORKSPACE_NAME" | cut -d= -f2)
DB_WORKSPACE=$(docker exec $POSTGRES psql -U dittofeed -d dittofeed -t -c "SELECT name FROM \"Workspace\" LIMIT 1;" 2>/dev/null | tr -d ' \n')

if [ "$WORKSPACE_NAME" != "$DB_WORKSPACE" ]; then
    echo "❌ ISSUE: Workspace name mismatch - Env: '$WORKSPACE_NAME', DB: '$DB_WORKSPACE'"
else
    echo "✅ Workspace name matches: $WORKSPACE_NAME"
fi

echo ""
echo "Recommendations:"
echo "----------------"
echo "1. Check if Next.js is running in production mode"
echo "2. Verify basePath configuration matches routing"
echo "3. Check for authentication requirements in multi-tenant mode"
echo "4. Review redirect configuration in next.config.js"