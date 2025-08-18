#!/bin/bash

# ==============================================================================
# Check Workspace Details and Fix API
# ==============================================================================

echo "===================================================="
echo "Checking Workspace and Fixing API"
echo "===================================================="

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Find containers
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)

echo "Step 1: Checking workspace details..."
echo ""
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain, created_at FROM \"Workspace\";" 2>/dev/null

echo ""
echo "Step 2: Checking API container status..."
API_STATUS=$(docker inspect -f '{{.State.Status}}' $API_CONTAINER 2>/dev/null)
API_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' $API_CONTAINER 2>/dev/null || echo "no healthcheck")
echo "API Container: $API_CONTAINER"
echo "Status: $API_STATUS"
echo "Health: $API_HEALTH"

echo ""
echo "Step 3: Checking API logs for errors..."
echo "Last 30 lines of API logs:"
docker logs $API_CONTAINER --tail 30 2>&1

echo ""
echo "Step 4: Checking if API process is running inside container..."
docker exec $API_CONTAINER ps aux | grep -E "node|npm" | head -5

echo ""
echo "Step 5: Restarting API container..."
docker restart $API_CONTAINER
echo "Waiting for API to start..."
sleep 10

echo ""
echo "Step 6: Checking API after restart..."
docker exec $API_CONTAINER sh -c "wget -qO- http://localhost:3001/api/public/health 2>/dev/null || curl -s http://localhost:3001/api/public/health 2>/dev/null" || echo "API still not responding"

echo ""
echo "Step 7: Getting container IPs..."
API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER | head -c -1 | tr -d '\n')
DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER | head -c -1 | tr -d '\n')
echo "API IP: $API_IP"
echo "Dashboard IP: $DASHBOARD_IP"

echo ""
echo "Step 8: Testing dashboard..."
docker exec $DASHBOARD_CONTAINER sh -c "ps aux | grep -E 'node|next'" | head -3

echo ""
echo "Step 9: Restarting dashboard..."
docker restart $DASHBOARD_CONTAINER
sleep 10

echo ""
echo "===================================================="
echo "Final Status"
echo "===================================================="

# Check all services
echo "Services status:"
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep "${PROJECT_ID}"

echo ""
echo "Workspace created:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT name || ' (' || domain || ')' as workspace FROM \"Workspace\";" 2>/dev/null

echo ""
echo "You should now be able to access:"
echo "  Dashboard: https://communication-dashboard.caramelme.com"
echo "  API: https://communication-api.caramelme.com"
echo ""
echo "If you still see 404, the issue might be with the dashboard not finding the workspace."
echo "The workspace domain should match your access domain."