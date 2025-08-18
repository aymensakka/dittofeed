#!/bin/bash

# ==============================================================================
# Check Bootstrap Status for Dittofeed Multi-Tenant
# ==============================================================================

set -e

echo "===================================================="
echo "Checking Bootstrap Status"
echo "===================================================="

# Find containers
PROJECT_ID="p0gcsc088cogco0cokco4404"
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)

echo "\nContainers found:"
echo "API: $API_CONTAINER"
echo "Postgres: $POSTGRES_CONTAINER"
echo "Dashboard: $DASHBOARD_CONTAINER"

# Check if database tables exist
if [ ! -z "$POSTGRES_CONTAINER" ]; then
    echo "\n📊 Checking database tables..."
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\dt" 2>/dev/null || echo "Failed to list tables"
    
    echo "\n🏢 Checking workspaces..."
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain, created_at FROM workspace;" 2>/dev/null || echo "No workspaces found or table doesn't exist"
    
    echo "\n👤 Checking workspace members..."
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT COUNT(*) as member_count FROM workspace_member;" 2>/dev/null || echo "No members found"
fi

# Check API logs for bootstrap
if [ ! -z "$API_CONTAINER" ]; then
    echo "\n📝 Recent API logs (looking for bootstrap):"
    docker logs $API_CONTAINER 2>&1 | tail -50 | grep -i "bootstrap\|migration\|workspace" || echo "No bootstrap-related logs found"
fi

# Check API health
if [ ! -z "$API_CONTAINER" ]; then
    echo "\n🔍 Checking API health:"
    docker exec $API_CONTAINER curl -s http://localhost:3001/api/public/health || echo "API health check failed"
fi

# Check dashboard status
if [ ! -z "$DASHBOARD_CONTAINER" ]; then
    echo "\n🖥️ Dashboard container status:"
    docker ps | grep $DASHBOARD_CONTAINER
fi

echo "\n===================================================="
echo "Bootstrap Status Check Complete"
echo "===================================================="