#!/bin/bash

# ==============================================================================
# Cleanup Duplicate OAuth Providers and Complete Setup
# ==============================================================================

set -e

echo "===================================================="
echo "Cleaning Up OAuth Providers"
echo "===================================================="
echo ""

PROJECT_ID="p0gcsc088cogco0cokco4404"
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "❌ PostgreSQL container not found"
    exit 1
fi

echo "PostgreSQL container: $POSTGRES_CONTAINER"
echo ""

# Step 1: Show current duplicates
echo "Step 1: Current AuthProvider entries..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "SELECT id, \"workspaceId\", type, enabled, config, \"createdAt\" FROM \"AuthProvider\" ORDER BY \"createdAt\";" 2>&1
echo ""

# Step 2: Remove duplicates, keeping the first one
echo "Step 2: Removing duplicate OAuth providers..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << 'EOF'
-- Delete duplicates, keeping the oldest one
DELETE FROM "AuthProvider" a
WHERE EXISTS (
    SELECT 1 FROM "AuthProvider" b
    WHERE b."workspaceId" = a."workspaceId"
    AND b.type = a.type
    AND b."createdAt" < a."createdAt"
);

-- Update the remaining entry with proper config
UPDATE "AuthProvider" 
SET 
    config = '{"provider": "google", "scope": ["openid", "email", "profile"]}',
    "updatedAt" = NOW()
WHERE type = 'google' 
AND (config IS NULL OR config = '{}');
EOF
echo "✅ Duplicates removed"
echo ""

# Step 3: Add missing columns
echo "Step 3: Ensuring all columns exist..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << 'EOF'
-- Add updatedAt if missing
ALTER TABLE "AuthProvider" 
ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL;

-- Ensure config has proper default
ALTER TABLE "AuthProvider" 
ALTER COLUMN config SET DEFAULT '{}';

-- Ensure workspaceId is NOT NULL
ALTER TABLE "AuthProvider" 
ALTER COLUMN "workspaceId" SET NOT NULL;
EOF
echo "✅ Columns verified"
echo ""

# Step 4: Create unique index
echo "Step 4: Creating unique index..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "CREATE UNIQUE INDEX IF NOT EXISTS \"AuthProvider_workspaceId_type_key\" ON \"AuthProvider\"(\"workspaceId\", type);" 2>&1
echo "✅ Index created"
echo ""

# Step 5: Verify final state
echo "Step 5: Final AuthProvider state..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "SELECT type, enabled, config, \"updatedAt\" FROM \"AuthProvider\";" 2>&1
echo ""

echo "Table structure:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\d \"AuthProvider\"" 2>&1 | head -25
echo ""

# Step 6: Check and restart services
echo "Step 6: Restarting services..."
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)

if [ ! -z "$API_CONTAINER" ]; then
    echo "Checking API logs before restart..."
    echo "Last 10 lines:"
    docker logs $API_CONTAINER --tail 10 2>&1
    echo ""
    
    docker restart $API_CONTAINER > /dev/null 2>&1
    echo "✅ API container restarted"
fi

if [ ! -z "$DASHBOARD_CONTAINER" ]; then
    docker restart $DASHBOARD_CONTAINER > /dev/null 2>&1
    echo "✅ Dashboard container restarted"
fi

echo ""
echo "⏳ Waiting for services to start..."
sleep 20

# Step 7: Test services
echo ""
echo "Step 7: Testing services..."
if [ ! -z "$API_CONTAINER" ]; then
    echo -n "API health check: "
    docker exec $API_CONTAINER curl -s -f http://localhost:3001/health >/dev/null 2>&1 && echo "✅ Healthy" || {
        echo "⚠️  Not ready"
        echo "API logs:"
        docker logs $API_CONTAINER --tail 20 2>&1
    }
fi

echo ""
echo -n "External API test: "
curl -s -o /dev/null -w "%{http_code}" https://communication-api.caramelme.com/health 2>/dev/null || echo "Failed"

echo ""
echo -n "Dashboard test: "
curl -s -o /dev/null -w "%{http_code}" https://communication-dashboard.caramelme.com/dashboard 2>/dev/null || echo "Failed"

echo ""
echo ""
echo "===================================================="
echo "OAuth Cleanup Complete!"
echo "===================================================="
echo ""
echo "✅ Duplicate OAuth providers removed"
echo "✅ AuthProvider table structure fixed"
echo "✅ Services restarted"
echo ""
echo "Test the application:"
echo "  https://communication-dashboard.caramelme.com/dashboard"
echo ""
echo "You should now see Google OAuth login!"
echo "===================================================="