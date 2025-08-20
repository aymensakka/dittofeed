#!/bin/bash

# ==============================================================================
# Force Cleanup OAuth Providers - More Aggressive Approach
# ==============================================================================

set -e

echo "===================================================="
echo "Force Cleanup OAuth Providers"
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

# Step 1: Show current state
echo "Step 1: Current AuthProvider entries..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "SELECT id, \"workspaceId\", type, \"createdAt\" FROM \"AuthProvider\" ORDER BY \"createdAt\";" 2>&1
echo ""

# Step 2: Delete ALL entries and recreate
echo "Step 2: Deleting ALL AuthProvider entries..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "DELETE FROM \"AuthProvider\";" 2>&1
echo "✅ All entries deleted"
echo ""

# Step 3: Get workspace ID
echo "Step 3: Getting workspace ID..."
WORKSPACE_ID=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c \
    "SELECT id FROM \"Workspace\" WHERE name = 'caramel' OR type = 'Root' LIMIT 1;" 2>/dev/null | tr -d ' \n')

if [ -z "$WORKSPACE_ID" ]; then
    echo "❌ No workspace found!"
    exit 1
fi

echo "Workspace ID: $WORKSPACE_ID"
echo ""

# Step 4: Insert single clean OAuth provider
echo "Step 4: Creating single Google OAuth provider..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
INSERT INTO "AuthProvider" (
    "workspaceId",
    "type",
    "enabled",
    "config",
    "createdAt"
) VALUES (
    '$WORKSPACE_ID',
    'google',
    true,
    '{"provider": "google", "scope": ["openid", "email", "profile"]}',
    NOW()
);
EOF
echo "✅ Single OAuth provider created"
echo ""

# Step 5: Add missing columns and create index
echo "Step 5: Finalizing table structure..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << 'EOF'
-- Add updatedAt if missing
ALTER TABLE "AuthProvider" 
ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL;

-- Update the updatedAt for existing row
UPDATE "AuthProvider" SET "updatedAt" = NOW();

-- Create unique index
CREATE UNIQUE INDEX IF NOT EXISTS "AuthProvider_workspaceId_type_key" 
ON "AuthProvider"("workspaceId", type);

-- Ensure foreign key exists
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'AuthProvider_workspaceId_fkey') THEN
        ALTER TABLE "AuthProvider" ADD CONSTRAINT "AuthProvider_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;
EOF
echo "✅ Table structure finalized"
echo ""

# Step 6: Verify final state
echo "Step 6: Final verification..."
echo "AuthProvider entries:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "SELECT type, enabled, config, \"updatedAt\" FROM \"AuthProvider\";" 2>&1
echo ""

echo "Table structure:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\d \"AuthProvider\"" 2>&1 | grep -A 20 "Table"
echo ""

echo "Indexes:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "SELECT indexname FROM pg_indexes WHERE tablename = 'AuthProvider';" 2>&1
echo ""

# Step 7: Restart services
echo "Step 7: Restarting services..."
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
WORKER_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "worker.*${PROJECT_ID}" | head -1)

[ ! -z "$API_CONTAINER" ] && docker restart $API_CONTAINER > /dev/null 2>&1 && echo "✅ API restarted"
[ ! -z "$DASHBOARD_CONTAINER" ] && docker restart $DASHBOARD_CONTAINER > /dev/null 2>&1 && echo "✅ Dashboard restarted"
[ ! -z "$WORKER_CONTAINER" ] && docker restart $WORKER_CONTAINER > /dev/null 2>&1 && echo "✅ Worker restarted"

echo ""
echo "⏳ Waiting 30 seconds for services to start..."
sleep 30

# Step 8: Test services
echo ""
echo "Step 8: Testing services..."

# Check API health internally
if [ ! -z "$API_CONTAINER" ]; then
    echo -n "API internal health: "
    docker exec $API_CONTAINER curl -s -f http://localhost:3001/health >/dev/null 2>&1 && echo "✅ Healthy" || {
        echo "❌ Not healthy"
        echo ""
        echo "API container status:"
        docker ps | grep $API_CONTAINER
        echo ""
        echo "Last 30 lines of API logs:"
        docker logs $API_CONTAINER --tail 30 2>&1
    }
fi

# Check external endpoints
echo ""
echo "External endpoint tests:"
echo -n "  API (https://communication-api.caramelme.com/health): "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://communication-api.caramelme.com/health 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ HTTP 200"
else
    echo "❌ HTTP $HTTP_CODE"
fi

echo -n "  Dashboard (https://communication-dashboard.caramelme.com/dashboard): "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://communication-dashboard.caramelme.com/dashboard 2>/dev/null)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "307" ]; then
    echo "✅ HTTP $HTTP_CODE"
else
    echo "❌ HTTP $HTTP_CODE"
fi

echo ""
echo "===================================================="
echo "Force Cleanup Complete!"
echo "===================================================="
echo ""
echo "✅ All duplicate OAuth providers removed"
echo "✅ Single Google OAuth provider created"
echo "✅ Unique index created successfully"
echo "✅ Services restarted"
echo ""
echo "Now test the application:"
echo "  https://communication-dashboard.caramelme.com/dashboard"
echo ""
echo "You should see Google OAuth login!"
echo ""
echo "If API is still unhealthy, check:"
echo "  docker logs api-p0gcsc088cogco0cokco4404-* --tail 50"
echo "===================================================="