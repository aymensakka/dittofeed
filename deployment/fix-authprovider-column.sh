#!/bin/bash

# ==============================================================================
# Direct Fix for AuthProvider Column Name
# ==============================================================================

set -e

echo "===================================================="
echo "Fixing AuthProvider Column Name"
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

# Step 1: Show current structure
echo "Step 1: Current AuthProvider structure..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\d \"AuthProvider\"" 2>&1 | head -20
echo ""

# Step 2: Rename the column directly
echo "Step 2: Renaming 'provider' column to 'type'..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "ALTER TABLE \"AuthProvider\" RENAME COLUMN provider TO type;" 2>&1 || {
    echo "Column might already be renamed or doesn't exist"
}
echo ""

# Step 3: Add missing columns if needed
echo "Step 3: Adding missing columns..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << 'EOF'
-- Add updatedAt if missing
ALTER TABLE "AuthProvider" 
ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL;

-- Ensure config has default value
ALTER TABLE "AuthProvider" 
ALTER COLUMN config SET DEFAULT '{}';

-- Update NULL configs
UPDATE "AuthProvider" 
SET config = '{"provider": "google", "scope": ["openid", "email", "profile"]}'
WHERE config IS NULL OR config = '{}';
EOF
echo ""

# Step 4: Verify the fix
echo "Step 4: Verifying fixed structure..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\d \"AuthProvider\"" 2>&1 | head -20
echo ""

# Step 5: Show data with correct column
echo "Step 5: AuthProvider entries..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "SELECT type, enabled, config FROM \"AuthProvider\";" 2>&1
echo ""

# Step 6: Ensure index exists
echo "Step 6: Creating unique index..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "CREATE UNIQUE INDEX IF NOT EXISTS \"AuthProvider_workspaceId_type_key\" ON \"AuthProvider\"(\"workspaceId\", type);" 2>&1
echo ""

echo "✅ AuthProvider column fixed!"
echo ""
echo "Restarting services..."
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)

[ ! -z "$API_CONTAINER" ] && docker restart $API_CONTAINER > /dev/null 2>&1
[ ! -z "$DASHBOARD_CONTAINER" ] && docker restart $DASHBOARD_CONTAINER > /dev/null 2>&1

echo "✅ Services restarted"
echo ""
echo "Wait 30 seconds then test:"
echo "  https://communication-dashboard.caramelme.com/dashboard"