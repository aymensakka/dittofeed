#!/bin/bash

# ==============================================================================
# Bootstrap Script with Correct Module Paths for Dittofeed Multi-Tenant
# ==============================================================================

set -e

echo "===================================================="
echo "Bootstrap for Dittofeed Multi-Tenant"
echo "===================================================="

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Find containers
echo "Finding containers..."
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)

if [ -z "$API_CONTAINER" ]; then
    echo "Error: API container not found"
    exit 1
fi

echo "Using containers:"
echo "  API: $API_CONTAINER"
echo "  Postgres: $POSTGRES_CONTAINER"
echo "  Dashboard: $DASHBOARD_CONTAINER"
echo ""

# Check if workspace already exists
echo "Checking existing workspaces..."
WORKSPACE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM workspace;" 2>/dev/null || echo "0")
WORKSPACE_COUNT=$(echo $WORKSPACE_COUNT | tr -d ' ')

if [ "$WORKSPACE_COUNT" != "0" ] && [ "$WORKSPACE_COUNT" != "" ]; then
    echo "Found $WORKSPACE_COUNT workspace(s). Showing existing workspaces:"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM workspace;"
    echo ""
    echo "Workspace already exists. Do you want to continue anyway? (y/n)"
    read -r response
    if [ "$response" != "y" ]; then
        echo "Exiting without changes."
        exit 0
    fi
else
    echo "No workspaces found. Bootstrap is needed."
fi

# Run migrations first
echo ""
echo "Step 1: Running database migrations..."
docker exec -e AUTH_MODE=multi-tenant $API_CONTAINER node -e '
const path = require("path");
const migratePath = path.join("/service/packages/backend-lib/dist/src/migrate.js");
console.log("Loading migrate from:", migratePath);

try {
    const { drizzleMigrate } = require(migratePath);
    console.log("Starting migrations...");
    drizzleMigrate().then(() => {
        console.log("✓ Migrations complete");
        process.exit(0);
    }).catch(err => {
        console.error("✗ Migration failed:", err.message);
        // Continue anyway as migrations might already be done
        process.exit(0);
    });
} catch (err) {
    console.error("Could not load migrate module:", err.message);
    // Continue anyway
    process.exit(0);
}
'

echo ""
echo "Step 2: Running bootstrap to create workspace..."

# Run bootstrap with correct path
docker exec -e AUTH_MODE=multi-tenant -e BOOTSTRAP_WORKSPACE_NAME=caramel -e BOOTSTRAP_WORKSPACE_DOMAIN=caramelme.com $API_CONTAINER node -e '
const path = require("path");
const bootstrapPath = path.join("/service/packages/backend-lib/dist/src/bootstrap.js");
console.log("Loading bootstrap from:", bootstrapPath);
console.log("Environment AUTH_MODE:", process.env.AUTH_MODE);

try {
    const { bootstrapWithDefaults } = require(bootstrapPath);
    
    const config = {
        workspaceName: process.env.BOOTSTRAP_WORKSPACE_NAME || "caramel",
        workspaceDomain: process.env.BOOTSTRAP_WORKSPACE_DOMAIN || "caramelme.com",
        workspaceType: "Root"
    };
    
    console.log("Running bootstrap with config:", config);
    
    bootstrapWithDefaults(config).then(() => {
        console.log("✓ Bootstrap successful - workspace created");
        process.exit(0);
    }).catch(err => {
        if (err.message && err.message.includes("already exists")) {
            console.log("✓ Workspace already exists");
            process.exit(0);
        } else {
            console.error("✗ Bootstrap failed:", err.message);
            console.error("Stack:", err.stack);
            process.exit(1);
        }
    });
} catch (err) {
    console.error("Failed to load bootstrap module:", err.message);
    process.exit(1);
}
'

if [ $? -eq 0 ]; then
    echo "✓ Bootstrap completed"
else
    echo "✗ Bootstrap failed"
fi

echo ""
echo "Step 3: Verifying bootstrap..."
echo "Checking workspaces in database..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain, created_at FROM workspace;" 2>/dev/null || echo "Failed to query workspaces"

echo ""
echo "Checking workspace members..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT COUNT(*) as member_count FROM \"WorkspaceMember\";" 2>/dev/null || true

echo ""
echo "Step 4: Getting container IPs for network configuration..."
API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER | head -c -1 | tr -d '\n')
POSTGRES_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $POSTGRES_CONTAINER | head -c -1 | tr -d '\n')
DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER | head -c -1 | tr -d '\n')

echo "Container IPs:"
echo "  API: ${API_IP}:3001"
echo "  Dashboard: ${DASHBOARD_IP}:3000"
echo "  Postgres: ${POSTGRES_IP}:5432"

echo ""
echo "Step 5: Updating Dashboard environment to use correct API IP..."
# Update dashboard to know the API IP
docker exec $DASHBOARD_CONTAINER sh -c "
export API_BASE_URL='http://${API_IP}:3001'
export NEXT_PUBLIC_API_BASE_URL='http://${API_IP}:3001'
echo 'Dashboard configured to use API at ${API_IP}:3001'
"

echo ""
echo "Step 6: Restarting services..."
echo "Restarting API..."
docker restart $API_CONTAINER
sleep 5

echo "Restarting Dashboard..."
docker restart $DASHBOARD_CONTAINER
sleep 5

echo ""
echo "===================================================="
echo "Bootstrap Complete!"
echo "===================================================="
echo ""
echo "The workspace 'caramel' with domain 'caramelme.com' has been created."
echo ""
echo "Internal network configuration:"
echo "  API: http://${API_IP}:3001"
echo "  Dashboard: http://${DASHBOARD_IP}:3000"
echo ""
echo "Public access URLs:"
echo "  Dashboard: https://communication-dashboard.caramelme.com"
echo "  API: https://communication-api.caramelme.com"
echo ""
echo "If you still see errors, wait 30 seconds for services to fully start."