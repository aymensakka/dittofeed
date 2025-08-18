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

# Show all containers first
echo "Current containers:"
docker ps --format 'table {{.Names}}	{{.Status}}' | grep -E "${PROJECT_ID}" | head -10
echo ""

# Find API container
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)

if [ -z "$API_CONTAINER" ]; then
    echo "Error: API container not found"
    echo "Trying alternative pattern..."
    API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i "api" | grep "${PROJECT_ID}" | head -1)
    if [ -z "$API_CONTAINER" ]; then
        echo "Still not found. Please check container names above."
        exit 1
    fi
fi

echo "Found API container: $API_CONTAINER"
echo ""

# Check working directory first
WORKDIR=$(docker exec $API_CONTAINER pwd)
echo "API container working directory: $WORKDIR"
echo ""

# First, run database migrations
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
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)

if [ ! -z "$POSTGRES_CONTAINER" ]; then
    echo "Checking database tables..."
    TABLE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')
    echo "Found $TABLE_COUNT tables in database"
    
    echo ""
    echo "Checking workspaces..."
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM workspace;" 2>/dev/null || echo "Failed to query workspaces"
fi

echo ""
echo "Step 4: Restarting dashboard to pick up changes..."
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
if [ ! -z "$DASHBOARD_CONTAINER" ]; then
    docker restart $DASHBOARD_CONTAINER
    echo "✓ Dashboard restarted"
fi

echo ""
echo "===================================================="
echo "Bootstrap Complete!"
echo "===================================================="
echo ""
echo "You should now be able to access:"
echo "  Dashboard: https://communication-dashboard.caramelme.com"
echo "  API: https://communication-api.caramelme.com"
echo ""
echo "The workspace 'caramel' with domain 'caramelme.com' has been created."
echo ""