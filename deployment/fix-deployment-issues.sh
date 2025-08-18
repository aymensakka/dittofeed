#!/bin/bash

# ==============================================================================
# Fix Deployment Issues - Clean up and verify workspace
# ==============================================================================

echo "===================================================="
echo "Fixing Deployment Issues"
echo "===================================================="

PROJECT_ID="p0gcsc088cogco0cokco4404"

echo "Step 1: Removing old dashboard container..."
OLD_DASHBOARD="dashboard-p0gcsc088cogco0cokco4404-161545882108"
docker stop $OLD_DASHBOARD 2>/dev/null && docker rm $OLD_DASHBOARD 2>/dev/null && echo "Removed old dashboard container" || echo "Old container not found or already removed"

echo ""
echo "Step 2: Checking Workspace table (case-sensitive)..."
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)

# Try different table name cases
echo "Trying 'Workspace' (capital W):"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain, created_at FROM \"Workspace\";" 2>/dev/null || echo "Not found with capital W"

echo ""
echo "Trying 'workspace' (lowercase):"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain, created_at FROM workspace;" 2>/dev/null || echo "Not found with lowercase"

echo ""
echo "Listing all tables to find the correct name:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\dt" 2>/dev/null | grep -i workspace

echo ""
echo "Step 3: Checking if workspace exists with correct query..."
WORKSPACE_EXISTS=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM \"Workspace\";" 2>/dev/null || echo "0")
WORKSPACE_EXISTS=$(echo $WORKSPACE_EXISTS | tr -d ' ')

if [ "$WORKSPACE_EXISTS" = "0" ] || [ -z "$WORKSPACE_EXISTS" ]; then
    echo "No workspace found. Creating one now..."
    
    # Create workspace directly in the database
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "
    INSERT INTO \"Workspace\" (id, name, type, domain, created_at, updated_at)
    VALUES (
        'workspace-' || substr(md5(random()::text), 1, 8),
        'caramel',
        'Root',
        'caramelme.com',
        NOW(),
        NOW()
    ) ON CONFLICT DO NOTHING;
    " 2>/dev/null && echo "Workspace created" || echo "Failed to create workspace"
    
    # Check again
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM \"Workspace\";" 2>/dev/null
else
    echo "Found $WORKSPACE_EXISTS workspace(s):"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM \"Workspace\";" 2>/dev/null
fi

echo ""
echo "Step 4: Checking API health issue..."
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)

echo "API logs (looking for errors):"
docker logs $API_CONTAINER --tail 50 2>&1 | grep -i "error\|fail\|cannot\|unable" | head -20 || echo "No obvious errors"

echo ""
echo "Checking API environment variables:"
docker exec $API_CONTAINER env | grep -E "AUTH_MODE|DATABASE_URL|WORKSPACE" | head -10

echo ""
echo "Step 5: Setting correct environment and restarting API..."
docker exec $API_CONTAINER sh -c "
export AUTH_MODE=multi-tenant
export DATABASE_URL=postgresql://dittofeed:password@postgres:5432/dittofeed
export BOOTSTRAP=false
" 2>/dev/null

docker restart $API_CONTAINER
echo "Waiting for API to stabilize..."
sleep 15

echo ""
echo "Step 6: Checking API health endpoint directly..."
API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER | head -c -1 | tr -d '\n')
echo "API IP: $API_IP"

# Try to access API health from dashboard container
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | grep -v "161545882108" | head -1)
echo "Testing API connectivity from dashboard container..."
docker exec $DASHBOARD_CONTAINER sh -c "wget -qO- http://$API_IP:3001/api/public/health 2>/dev/null" || echo "Could not reach API from dashboard"

echo ""
echo "Step 7: Final status check..."
echo ""
echo "Containers running:"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.State}}' | grep "${PROJECT_ID}" | grep -v "161545882108"

echo ""
echo "Workspace in database:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM \"Workspace\";" 2>/dev/null

echo ""
echo "===================================================="
echo "Summary"
echo "===================================================="

WORKSPACE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM \"Workspace\";" 2>/dev/null || echo "0")
WORKSPACE_COUNT=$(echo $WORKSPACE_COUNT | tr -d ' ')

if [ "$WORKSPACE_COUNT" != "0" ]; then
    echo "✓ Workspace exists in database"
else
    echo "✗ No workspace in database - bootstrap needs to be run again"
fi

# Check if API is responding
docker exec $API_CONTAINER sh -c "wget -qO- http://localhost:3001/api/public/health 2>/dev/null" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ API is responding"
else
    echo "✗ API is not responding - may need configuration fixes"
fi

echo ""
echo "Try accessing: https://communication-dashboard.caramelme.com"
echo ""
echo "If still getting 404, run: ./deployment/bootstrap-correct-path.sh"