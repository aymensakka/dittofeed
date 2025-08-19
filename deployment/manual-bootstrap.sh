#!/bin/bash

# ==============================================================================
# Manual Bootstrap Script - Create workspace and initialize database
# Use this for: Initial setup, creating workspaces, fixing missing workspaces
# ==============================================================================

set -e

echo "===================================================="
echo "Manual Bootstrap for Dittofeed Multi-Tenant"
echo "===================================================="

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Function to find containers dynamically
find_containers() {
    API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
    POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
    DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
    WORKER_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "worker.*${PROJECT_ID}" | head -1)
}

# Find all containers
echo "Finding containers..."
find_containers

echo "Found containers:"
echo "  API: ${API_CONTAINER:-NOT FOUND}"
echo "  Postgres: ${POSTGRES_CONTAINER:-NOT FOUND}"
echo "  Dashboard: ${DASHBOARD_CONTAINER:-NOT FOUND}"
echo "  Worker: ${WORKER_CONTAINER:-NOT FOUND}"
echo ""

# Check critical containers
if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "❌ PostgreSQL container not found. Cannot proceed."
    exit 1
fi

# Check existing workspaces
echo "Checking existing workspaces..."
WORKSPACE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM \"Workspace\";" 2>/dev/null || echo "0")
WORKSPACE_COUNT=$(echo $WORKSPACE_COUNT | tr -d ' ')

if [ "$WORKSPACE_COUNT" != "0" ]; then
    echo "Found $WORKSPACE_COUNT workspace(s):"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, status FROM \"Workspace\";" 2>/dev/null
    echo ""
    echo "Do you want to create another workspace? (y/n)"
    read -r response
    if [ "$response" != "y" ]; then
        echo "Exiting without changes."
        exit 0
    fi
fi

# Ask for workspace details
echo ""
echo "Enter workspace name (default: caramel):"
read -r WORKSPACE_NAME
WORKSPACE_NAME=${WORKSPACE_NAME:-caramel}

echo "Enter workspace domain (default: caramelme.com):"
read -r WORKSPACE_DOMAIN
WORKSPACE_DOMAIN=${WORKSPACE_DOMAIN:-caramelme.com}

# Method 1: Try using API container bootstrap if available
if [ ! -z "$API_CONTAINER" ]; then
    echo ""
    echo "Method 1: Attempting bootstrap via API container..."
    
    # Check working directory
    WORKDIR=$(docker exec $API_CONTAINER pwd 2>/dev/null || echo "/service")
    echo "API working directory: $WORKDIR"
    
    # Run migrations first (optional - they may already be done)
    echo "Running migrations (if needed)..."
    docker exec -e AUTH_MODE=multi-tenant $API_CONTAINER node -e "
    const path = require('path');
    const migratePath = path.join('/service/packages/backend-lib/dist/src/migrate.js');
    try {
        const { drizzleMigrate } = require(migratePath);
        drizzleMigrate().then(() => {
            console.log('✓ Migrations complete');
            process.exit(0);
        }).catch(err => {
            console.log('Migrations may already be done:', err.message);
            process.exit(0);
        });
    } catch (err) {
        console.log('Could not run migrations:', err.message);
        process.exit(0);
    }
    " 2>/dev/null || true
    
    # Try to run bootstrap
    docker exec -e AUTH_MODE=multi-tenant $API_CONTAINER node -e "
    const path = require('path');
    const bootstrapPath = path.join('/service/packages/backend-lib/dist/src/bootstrap.js');
    
    try {
        const { bootstrapWithDefaults } = require(bootstrapPath);
        console.log('Running bootstrap...');
        bootstrapWithDefaults({
            workspaceName: '$WORKSPACE_NAME',
            workspaceDomain: '$WORKSPACE_DOMAIN',
            workspaceType: 'Root'
        }).then(() => {
            console.log('✅ Bootstrap successful');
            process.exit(0);
        }).catch(err => {
            if (err.message && err.message.includes('already exists')) {
                console.log('✅ Workspace already exists');
                process.exit(0);
            } else {
                console.error('Bootstrap failed:', err.message);
                process.exit(1);
            }
        });
    } catch (err) {
        console.error('Could not load bootstrap module:', err.message);
        process.exit(1);
    }
    " 2>/dev/null && METHOD1_SUCCESS=true || METHOD1_SUCCESS=false
    
    if [ "$METHOD1_SUCCESS" = "true" ]; then
        echo "✅ Bootstrap successful via API"
    else
        echo "⚠️  Bootstrap via API failed, trying direct database method..."
    fi
else
    echo "⚠️  API container not found, using direct database method..."
    METHOD1_SUCCESS=false
fi

# Method 2: Direct database insertion if Method 1 failed
if [ "$METHOD1_SUCCESS" = "false" ]; then
    echo ""
    echo "Method 2: Creating workspace directly in database..."
    
    WORKSPACE_ID=$(uuidgen 2>/dev/null || echo "ws-$(date +%s)")
    
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
INSERT INTO "Workspace" (
    id,
    name,
    type,
    status,
    "createdAt",
    "updatedAt"
) VALUES (
    '$WORKSPACE_ID',
    '$WORKSPACE_NAME',
    'Root',
    'Active',
    NOW(),
    NOW()
) ON CONFLICT (name) DO NOTHING;
EOF
    
    echo "✅ Workspace created in database"
    
    # Create default user properties
    echo "Creating default user properties..."
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
INSERT INTO "UserProperty" (id, "workspaceId", name, definition, "createdAt", "updatedAt")
SELECT 
    gen_random_uuid()::text,
    '$WORKSPACE_ID',
    prop.name,
    prop.definition::jsonb,
    NOW(),
    NOW()
FROM (
    VALUES 
        ('email', '{"type": "Trait"}'),
        ('firstName', '{"type": "Trait"}'),
        ('lastName', '{"type": "Trait"}'),
        ('phone', '{"type": "Trait"}'),
        ('id', '{"type": "Id"}'),
        ('anonymousId', '{"type": "AnonymousId"}')
) AS prop(name, definition)
WHERE NOT EXISTS (
    SELECT 1 FROM "UserProperty" 
    WHERE "workspaceId" = '$WORKSPACE_ID' AND name = prop.name
);
EOF
fi

# Verify workspace was created
echo ""
echo "Verifying workspace creation..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, status FROM \"Workspace\" WHERE name = '$WORKSPACE_NAME';" 2>/dev/null

# Get current IPs
echo ""
echo "Getting container IPs..."
API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')
DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')

# Fix database schema for multi-tenant support
echo ""
echo "Fixing database schema for multi-tenant support..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "ALTER TABLE \"Workspace\" ADD COLUMN IF NOT EXISTS domain TEXT;" 2>/dev/null || true
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "ALTER TABLE \"Workspace\" ADD COLUMN IF NOT EXISTS \"externalId\" TEXT;" 2>/dev/null || true
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "ALTER TABLE \"Workspace\" ADD COLUMN IF NOT EXISTS \"parentWorkspaceId\" UUID REFERENCES \"Workspace\"(id);" 2>/dev/null || true
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "ALTER TABLE \"WorkspaceMemberRole\" ADD COLUMN IF NOT EXISTS \"resourceType\" TEXT;" 2>/dev/null || true
DOMAIN="${DOMAIN:-caramelme.com}"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "UPDATE \"Workspace\" SET domain = '$DOMAIN' WHERE domain IS NULL;" 2>/dev/null || true
echo "✅ Database schema updated"

# Restart services
echo ""
echo "Restarting services..."
[ ! -z "$API_CONTAINER" ] && docker restart $API_CONTAINER > /dev/null 2>&1
sleep 5
[ ! -z "$DASHBOARD_CONTAINER" ] && docker restart $DASHBOARD_CONTAINER > /dev/null 2>&1
sleep 5

# Re-find containers and get new IPs (in case they changed)
find_containers
NEW_API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')
NEW_DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')

# Check if IPs changed
if [ "$API_IP" != "$NEW_API_IP" ] || [ "$DASHBOARD_IP" != "$NEW_DASHBOARD_IP" ]; then
    echo ""
    echo "⚠️  Container IPs changed after restart!"
    API_IP=$NEW_API_IP
    DASHBOARD_IP=$NEW_DASHBOARD_IP
fi

echo ""
echo "===================================================="
echo "Bootstrap Complete!"
echo "===================================================="
echo ""
echo "Workspace '$WORKSPACE_NAME' has been created."
echo ""
echo "Container IPs:"
echo "  API: ${API_IP}:3001"
echo "  Dashboard: ${DASHBOARD_IP}:3000"
echo ""
echo "Cloudflare Tunnel Configuration:"
echo "  communication-api.caramelme.com → http://${API_IP}:3001"
echo "  communication-dashboard.caramelme.com → http://${DASHBOARD_IP}:3000"
echo ""
echo "Access URL: https://communication-dashboard.caramelme.com"
echo ""

# Save configuration
cat > /tmp/dittofeed-config.txt << EOF
Dittofeed Configuration - $(date)
=====================================
Workspace: $WORKSPACE_NAME
Domain: $WORKSPACE_DOMAIN

API: http://${API_IP}:3001
Dashboard: http://${DASHBOARD_IP}:3000

Cloudflare Tunnel:
- communication-api.caramelme.com → http://${API_IP}:3001
- communication-dashboard.caramelme.com → http://${DASHBOARD_IP}:3000
EOF

echo "Configuration saved to: /tmp/dittofeed-config.txt"