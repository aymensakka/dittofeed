#!/bin/bash

# ==============================================================================
# Coolify Post-Deployment Script for Dittofeed Multi-Tenant
# This script runs automatically after Coolify deploys the containers
# ==============================================================================

set -e

echo "===================================================="
echo "Running Post-Deployment Bootstrap"
echo "===================================================="

PROJECT_ID="${COOLIFY_PROJECT_ID:-p0gcsc088cogco0cokco4404}"

# Wait for services to be ready
echo "Waiting for services to stabilize..."
sleep 10

# Find API container
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)

if [ -z "$API_CONTAINER" ]; then
    echo "Warning: API container not found, skipping bootstrap"
    exit 0
fi

echo "Found API container: $API_CONTAINER"

# Check if database is already bootstrapped by looking for workspaces
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
if [ ! -z "$POSTGRES_CONTAINER" ]; then
    WORKSPACE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM workspace;" 2>/dev/null || echo "0")
    WORKSPACE_COUNT=$(echo $WORKSPACE_COUNT | tr -d ' ')
    
    if [ "$WORKSPACE_COUNT" != "0" ] && [ "$WORKSPACE_COUNT" != "" ]; then
        echo "Database already bootstrapped (found $WORKSPACE_COUNT workspace(s)), skipping..."
        exit 0
    fi
fi

echo "Running database migrations..."
docker exec $API_CONTAINER sh -c "cd /app && node -e '
const { drizzleMigrate } = require(\"backend-lib/dist/migrate\");
console.log(\"Starting migrations...\");
drizzleMigrate().then(() => {
  console.log(\"✓ Migrations complete\");
}).catch(err => {
  console.error(\"✗ Migration failed:\", err.message);
  // Don not fail deployment if migrations fail (might already be done)
});
'" || true

echo "Running bootstrap to create initial workspace..."
docker exec $API_CONTAINER sh -c "cd /app && node -e '
const { bootstrapWithDefaults } = require(\"backend-lib/dist/bootstrap\");
console.log(\"Starting bootstrap...\");
bootstrapWithDefaults({
  workspaceName: process.env.BOOTSTRAP_WORKSPACE_NAME || \"Default\",
  workspaceDomain: process.env.BOOTSTRAP_WORKSPACE_DOMAIN || undefined,
  workspaceType: process.env.BOOTSTRAP_WORKSPACE_TYPE || \"Root\"
}).then(() => {
  console.log(\"✓ Bootstrap successful\");
}).catch(err => {
  if (err.message && err.message.includes(\"already exists\")) {
    console.log(\"✓ Workspace already exists\");
  } else {
    console.error(\"✗ Bootstrap failed:\", err.message);
    // Don not fail deployment
  }
});
'" || true

# Restart dashboard to ensure it picks up the new configuration
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
if [ ! -z "$DASHBOARD_CONTAINER" ]; then
    echo "Restarting dashboard..."
    docker restart $DASHBOARD_CONTAINER
fi

echo "===================================================="
echo "Post-Deployment Bootstrap Complete"
echo "===================================================="

# Always exit 0 to not fail the deployment
exit 0