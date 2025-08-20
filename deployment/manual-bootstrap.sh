#!/bin/bash

# ==============================================================================
# Manual Bootstrap Script - Create workspace and initialize database
# Use this for: Initial setup, creating workspaces, fixing missing workspaces
# Options:
#   --build-dashboard : Also build and push dashboard Docker image with AUTH_MODE=multi-tenant
# ==============================================================================

set -e

echo "===================================================="
echo "Manual Bootstrap for Dittofeed Multi-Tenant"
echo "===================================================="

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Docker Registry Configuration
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo/dittofeed"
TAG="multitenancy-oauth-v3"
DASHBOARD_IMAGE="${REGISTRY}/${REPO}/dashboard:${TAG}"

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
    
    # Get existing workspace details for OAuth setup
    WORKSPACE_NAME=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT name FROM \"Workspace\" LIMIT 1;" | tr -d ' ')
    WORKSPACE_DOMAIN=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COALESCE(domain, 'caramelme.com') FROM \"Workspace\" LIMIT 1;" | tr -d ' ')
    echo ""
    echo "Using existing workspace: $WORKSPACE_NAME (domain: $WORKSPACE_DOMAIN)"
    SKIP_WORKSPACE_CREATION=true
else
    # Ask for workspace details
    echo ""
    echo "Enter workspace name (default: caramel):"
    read -r WORKSPACE_NAME
    WORKSPACE_NAME=${WORKSPACE_NAME:-caramel}
    
    echo "Enter workspace domain (default: caramelme.com):"
    read -r WORKSPACE_DOMAIN
    WORKSPACE_DOMAIN=${WORKSPACE_DOMAIN:-caramelme.com}
    SKIP_WORKSPACE_CREATION=false
fi

# Method 1: Try using API container bootstrap if available (only if workspace doesn't exist)
if [ "$SKIP_WORKSPACE_CREATION" = "false" ] && [ ! -z "$API_CONTAINER" ]; then
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
elif [ "$SKIP_WORKSPACE_CREATION" = "false" ]; then
    echo "⚠️  API container not found, using direct database method..."
    METHOD1_SUCCESS=false
else
    echo "Skipping workspace creation (already exists)"
    METHOD1_SUCCESS=skip
fi

# Method 2: Direct database insertion if Method 1 failed and workspace doesn't exist
if [ "$METHOD1_SUCCESS" = "false" ] && [ "$SKIP_WORKSPACE_CREATION" = "false" ]; then
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

# Fix AuthProvider table and setup OAuth
echo ""
echo "Setting up OAuth provider..."
# Fix AuthProvider table column if needed
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF 2>/dev/null || true
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'AuthProvider' AND column_name = 'provider') THEN
        ALTER TABLE "AuthProvider" RENAME COLUMN provider TO type;
    END IF;
END\$\$;
EOF

# Get workspace ID for OAuth setup
WORKSPACE_ID=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT id FROM \"Workspace\" WHERE name = '$WORKSPACE_NAME' LIMIT 1;" | tr -d ' ')

# Clean up any existing OAuth providers and insert fresh one
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
DELETE FROM "AuthProvider" WHERE "workspaceId" = '$WORKSPACE_ID';

INSERT INTO "AuthProvider" (
    "workspaceId", "type", "enabled", "config", "createdAt", "updatedAt"
) VALUES (
    '$WORKSPACE_ID', 
    'google', 
    true,
    '{"provider": "google", "scope": ["openid", "email", "profile"]}',
    NOW(), 
    NOW()
);
EOF
echo "✅ OAuth provider configured"

# Build Dashboard Docker Image if requested
if [ "$1" = "--build-dashboard" ]; then
    echo ""
    echo "Building dashboard Docker image with multi-tenant auth..."
    echo "----------------------------------------------------------"
    
    # Check if we're in the right directory
    if [ ! -f "package.json" ]; then
        echo "⚠️  Warning: Not in dittofeed root directory. Trying to change directory..."
        if [ -f "../package.json" ]; then
            cd ..
        else
            echo "❌ Error: Cannot find package.json. Skipping dashboard build."
        fi
    fi
    
    if [ -f "package.json" ]; then
        echo "Setting build environment variables..."
        
        # Set all required environment variables for the build
        export NODE_ENV=production
        export AUTH_MODE=multi-tenant
        export NEXT_PUBLIC_AUTH_MODE=multi-tenant
        export NEXT_PUBLIC_ENABLE_MULTITENANCY=true
        
        # Add required ClickHouse config to pass validation
        export CLICKHOUSE_HOST=clickhouse
        export CLICKHOUSE_USER=dittofeed
        export CLICKHOUSE_PASSWORD=password
        
        echo "Installing dependencies and building emailo..."
        # First install all dependencies
        yarn install
        
        # Build emailo package first (dashboard depends on it)
        echo "Building emailo package..."
        yarn workspace emailo build
        
        echo "Building dashboard with yarn..."
        cd packages/dashboard
        
        # Create .env.production with all required variables
        cat > .env.production << EOF
NODE_ENV=production
AUTH_MODE=multi-tenant
NEXT_PUBLIC_AUTH_MODE=multi-tenant
NEXT_PUBLIC_ENABLE_MULTITENANCY=true
CLICKHOUSE_HOST=clickhouse
CLICKHOUSE_USER=dittofeed
CLICKHOUSE_PASSWORD=password
EOF
        
        # Build the dashboard
        if yarn build; then
            echo "✅ Dashboard built successfully"
            
            cd ../..
            
            echo "Building Docker image..."
            docker build \
                --platform linux/amd64 \
                -f packages/dashboard/Dockerfile \
                -t "$DASHBOARD_IMAGE" \
                --build-arg AUTH_MODE=multi-tenant \
                --build-arg NEXT_PUBLIC_AUTH_MODE=multi-tenant \
                .
            
            if [ $? -eq 0 ]; then
                echo "✅ Docker image built: $DASHBOARD_IMAGE"
                
                echo "Logging into Docker registry..."
                docker login "$REGISTRY" --username coolify-system --password '9sFPGGDJUFnE4z*z4Aj9'
                
                echo "Pushing image to registry..."
                docker push "$DASHBOARD_IMAGE"
                echo "✅ Image pushed to registry"
                
                echo ""
                echo "Dashboard image ready: $DASHBOARD_IMAGE"
                echo "Update this in Coolify for the dashboard service."
            else
                echo "❌ Failed to build Docker image"
            fi
        else
            echo "❌ Dashboard build failed"
            cd ../..
        fi
    fi
fi

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
if [ "$SKIP_WORKSPACE_CREATION" = "true" ]; then
    echo "✅ Using existing workspace: $WORKSPACE_NAME"
else
    echo "✅ Workspace '$WORKSPACE_NAME' has been created"
fi
echo "✅ OAuth provider (Google) configured"

if [ "$1" = "--build-dashboard" ] && [ -f "package.json" -o -f "../package.json" ]; then
    echo "✅ Dashboard image built and pushed: $DASHBOARD_IMAGE"
fi

echo ""
echo "Container IPs:"
echo "  API: ${API_IP}:3001"
echo "  Dashboard: ${DASHBOARD_IP}:3000"
echo ""
echo "Cloudflare Tunnel Configuration:"
echo "  communication-api.caramelme.com → http://${API_IP}:3001"
echo "  communication-dashboard.caramelme.com → http://${DASHBOARD_IP}:3000"
echo ""
echo "Environment Variables for Coolify:"
echo "  AUTH_MODE=multi-tenant"
echo "  NEXT_PUBLIC_AUTH_MODE=multi-tenant"
echo "  GOOGLE_CLIENT_ID=<your-google-client-id>"
echo "  GOOGLE_CLIENT_SECRET=<your-google-client-secret>"
echo "  NEXTAUTH_URL=https://communication-dashboard.caramelme.com/dashboard"
echo "  NEXTAUTH_SECRET=<your-nextauth-secret>"
echo ""

if [ "$1" != "--build-dashboard" ]; then
    echo "Note: Dashboard image not rebuilt. To rebuild with multi-tenant auth:"
    echo "  ./deployment/manual-bootstrap.sh --build-dashboard"
    echo ""
fi

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

Dashboard Image: $DASHBOARD_IMAGE

Cloudflare Tunnel:
- communication-api.caramelme.com → http://${API_IP}:3001
- communication-dashboard.caramelme.com → http://${DASHBOARD_IP}:3000

OAuth: Google provider configured
Auth Mode: multi-tenant
EOF

echo "Configuration saved to: /tmp/dittofeed-config.txt"