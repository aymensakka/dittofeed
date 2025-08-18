#!/bin/bash

# ==============================================================================
# Simple Bootstrap Script - Quick workspace creation and status check
# Use this for: Quick checks, simple bootstrap, verifying deployment
# ==============================================================================

set -e

echo "===================================================="
echo "Simple Bootstrap and Status Check"
echo "===================================================="

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Function to find containers
find_containers() {
    API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
    POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
    DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
    WORKER_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "worker.*${PROJECT_ID}" | head -1)
    TEMPORAL_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "temporal.*${PROJECT_ID}" | head -1)
    CLICKHOUSE_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "clickhouse.*${PROJECT_ID}" | head -1)
    REDIS_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "redis.*${PROJECT_ID}" | head -1)
}

# Find containers
find_containers

echo "Containers found:"
echo "  API: ${API_CONTAINER:-NOT FOUND}"
echo "  Dashboard: ${DASHBOARD_CONTAINER:-NOT FOUND}"
echo "  Postgres: ${POSTGRES_CONTAINER:-NOT FOUND}"
echo "  Worker: ${WORKER_CONTAINER:-NOT FOUND}"
echo "  Temporal: ${TEMPORAL_CONTAINER:-NOT FOUND}"
echo "  ClickHouse: ${CLICKHOUSE_CONTAINER:-NOT FOUND}"
echo "  Redis: ${REDIS_CONTAINER:-NOT FOUND}"
echo ""

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "❌ PostgreSQL container not found. Cannot proceed."
    exit 1
fi

# Check database status
echo "Checking database status..."
TABLE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
TABLE_COUNT=$(echo $TABLE_COUNT | tr -d ' ')
echo "  Tables in database: $TABLE_COUNT"

# Show table names if verbose mode
if [ "$1" = "-v" ] || [ "$1" = "--verbose" ]; then
    echo ""
    echo "Database tables:"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\dt" 2>/dev/null | head -20
    
    echo ""
    echo "Workspace table structure:"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\d \"Workspace\"" 2>/dev/null | head -15
fi

# Check workspaces
WORKSPACE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM \"Workspace\";" 2>/dev/null || echo "0")
WORKSPACE_COUNT=$(echo $WORKSPACE_COUNT | tr -d ' ')
echo "  Workspaces: $WORKSPACE_COUNT"

if [ "$WORKSPACE_COUNT" != "0" ]; then
    echo ""
    echo "Existing workspaces:"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, status FROM \"Workspace\";" 2>/dev/null
fi

# Get container IPs
echo ""
echo "Container IPs:"
[ ! -z "$API_CONTAINER" ] && echo "  API: $(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER 2>/dev/null | head -c -1):3001"
[ ! -z "$DASHBOARD_CONTAINER" ] && echo "  Dashboard: $(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER 2>/dev/null | head -c -1):3000"
[ ! -z "$POSTGRES_CONTAINER" ] && echo "  Postgres: $(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $POSTGRES_CONTAINER 2>/dev/null | head -c -1):5432"

# Check service health
echo ""
echo "Service Health:"
for container in "$API_CONTAINER" "$DASHBOARD_CONTAINER" "$WORKER_CONTAINER" "$TEMPORAL_CONTAINER" "$POSTGRES_CONTAINER" "$CLICKHOUSE_CONTAINER" "$REDIS_CONTAINER"; do
    if [ ! -z "$container" ]; then
        STATUS=$(docker inspect -f '{{.State.Status}}' $container 2>/dev/null)
        HEALTH=$(docker inspect -f '{{.State.Health.Status}}' $container 2>/dev/null || echo "no healthcheck")
        printf "  %-50s %s (health: %s)\n" "$container:" "$STATUS" "$HEALTH"
    fi
done

echo ""
echo "===================================================="
echo "Summary"
echo "===================================================="

if [ "$TABLE_COUNT" -lt "30" ]; then
    echo "⚠️  Database not initialized (only $TABLE_COUNT tables)"
    echo "   Run: ./deployment/manual-bootstrap.sh"
elif [ "$WORKSPACE_COUNT" = "0" ]; then
    echo "⚠️  No workspace exists"
    echo "   Run: ./deployment/manual-bootstrap.sh"
else
    echo "✅ Database initialized with $TABLE_COUNT tables"
    echo "✅ $WORKSPACE_COUNT workspace(s) exist"
    
    # Get IPs for Cloudflare
    API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER 2>/dev/null | head -c -1)
    DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER 2>/dev/null | head -c -1)
    
    echo ""
    echo "Cloudflare Tunnel Configuration:"
    echo "  communication-api.caramelme.com → http://${API_IP}:3001"
    echo "  communication-dashboard.caramelme.com → http://${DASHBOARD_IP}:3000"
fi

echo ""
echo "Access URL: https://communication-dashboard.caramelme.com"
echo ""
echo "For more details, run: $0 --verbose"