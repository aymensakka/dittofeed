#!/bin/bash

# ==============================================================================
# Manual Bootstrap Script for Dittofeed Multi-Tenant
# Run this on the server to manually trigger bootstrap
# ==============================================================================

set -e

echo "===================================================="
echo "Manual Bootstrap for Dittofeed Multi-Tenant"
echo "===================================================="

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Find all containers dynamically
echo "Finding containers..."
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
WORKER_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "worker.*${PROJECT_ID}" | head -1)
TEMPORAL_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "temporal.*${PROJECT_ID}" | head -1)
CLICKHOUSE_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "clickhouse.*${PROJECT_ID}" | head -1)
REDIS_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "redis.*${PROJECT_ID}" | head -1)

echo ""
echo "Found containers:"
echo "  API: ${API_CONTAINER:-NOT FOUND}"
echo "  Postgres: ${POSTGRES_CONTAINER:-NOT FOUND}"
echo "  Dashboard: ${DASHBOARD_CONTAINER:-NOT FOUND}"
echo "  Worker: ${WORKER_CONTAINER:-NOT FOUND}"
echo "  Temporal: ${TEMPORAL_CONTAINER:-NOT FOUND}"
echo "  ClickHouse: ${CLICKHOUSE_CONTAINER:-NOT FOUND}"
echo "  Redis: ${REDIS_CONTAINER:-NOT FOUND}"
echo ""

# Check critical containers
if [ -z "$API_CONTAINER" ]; then
    echo "Error: API container not found"
    echo "Current running containers:"
    docker ps --format 'table {{.Names}}	{{.Status}}' | grep "${PROJECT_ID}"
    exit 1
fi

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "Error: Postgres container not found"
    exit 1
fi

# Check working directory
WORKDIR=$(docker exec $API_CONTAINER pwd 2>/dev/null || echo "/service")
echo "API container working directory: $WORKDIR"
echo ""

# Check if workspace already exists
echo "Checking existing workspaces..."
WORKSPACE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM workspace;" 2>/dev/null || echo "0")
WORKSPACE_COUNT=$(echo $WORKSPACE_COUNT | tr -d ' ')

if [ "$WORKSPACE_COUNT" != "0" ] && [ "$WORKSPACE_COUNT" != "" ]; then
    echo "Found $WORKSPACE_COUNT workspace(s). Showing existing workspaces:"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM workspace;"
    echo ""
    echo "Workspace already exists. Bootstrap may not be needed."
    echo "Do you want to continue anyway? (y/n)"
    read -r response
    if [ "$response" != "y" ]; then
        echo "Exiting without changes."
        exit 0
    fi
else
    echo "No workspaces found. Bootstrap is needed."
fi

echo ""
echo "Step 1: Running database migrations..."
docker exec $API_CONTAINER node -e '
const { drizzleMigrate } = require("./node_modules/backend-lib/dist/migrate");
console.log("Starting migrations...");
drizzleMigrate().then(() => {
  console.log("✓ Migrations complete");
  process.exit(0);
}).catch(err => {
  console.error("✗ Migration failed:", err);
  process.exit(1);
});
'

if [ $? -eq 0 ]; then
    echo "✓ Migrations successful"
else
    echo "✗ Migrations failed, but continuing..."
fi

echo ""
echo "Step 2: Running bootstrap to create workspace..."

# Run bootstrap with multi-tenant configuration
docker exec -e AUTH_MODE=multi-tenant $API_CONTAINER node -e '
process.env.AUTH_MODE = "multi-tenant";
const { bootstrapWithDefaults } = require("./node_modules/backend-lib/dist/bootstrap");
console.log("Starting bootstrap with AUTH_MODE:", process.env.AUTH_MODE);
bootstrapWithDefaults({
  workspaceName: "caramel",
  workspaceDomain: "caramelme.com",
  workspaceType: "Root"
}).then(() => {
  console.log("✓ Bootstrap successful - workspace created");
  process.exit(0);
}).catch(err => {
  if (err.message && err.message.includes("already exists")) {
    console.log("✓ Workspace already exists");
    process.exit(0);
  } else {
    console.error("✗ Bootstrap failed:", err);
    process.exit(1);
  }
});
'

if [ $? -eq 0 ]; then
    echo "✓ Bootstrap successful"
else
    echo "✗ Bootstrap failed"
    exit 1
fi

echo ""
echo "Step 3: Verifying bootstrap..."

# Check if tables and workspace were created
echo "Checking database tables..."
TABLE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')
echo "Found $TABLE_COUNT tables in database"

echo ""
echo "Checking workspaces..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM workspace;" 2>/dev/null || echo "Failed to query workspaces"

echo ""
echo "Step 4: Restarting services to pick up changes..."
if [ ! -z "$DASHBOARD_CONTAINER" ]; then
    docker restart $DASHBOARD_CONTAINER
    echo "✓ Dashboard restarted"
else
    echo "⚠ Dashboard container not found, skipping restart"
fi

if [ ! -z "$API_CONTAINER" ]; then
    docker restart $API_CONTAINER
    echo "✓ API restarted"
fi

echo ""
echo "===================================================="
echo "Bootstrap Complete!"
echo "===================================================="
echo ""
echo "Services status:"
echo "  API: $(docker ps --format '{{.Status}}' --filter "name=$API_CONTAINER")"
echo "  Dashboard: $(docker ps --format '{{.Status}}' --filter "name=$DASHBOARD_CONTAINER")"
echo "  Worker: $(docker ps --format '{{.Status}}' --filter "name=$WORKER_CONTAINER")"
echo ""
echo "You should now be able to access:"
echo "  Dashboard: https://communication-dashboard.caramelme.com"
echo "  API: https://communication-api.caramelme.com"
echo ""
echo "The workspace 'caramel' with domain 'caramelme.com' has been created."
echo ""