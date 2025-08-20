#!/bin/bash

# ==============================================================================
# Fix AuthProvider Schema - Correct column names
# ==============================================================================

set -e

echo "===================================================="
echo "Fixing AuthProvider Schema"
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

# Step 1: Check current schema
echo "Step 1: Current AuthProvider schema..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\d \"AuthProvider\"" 2>&1 | head -20
echo ""

# Step 2: Fix column names
echo "Step 2: Fixing column names..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << 'EOF'
-- Check if we need to rename columns
DO $$ 
BEGIN
    -- Rename 'provider' to 'type' if it exists
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'AuthProvider' AND column_name = 'provider') THEN
        ALTER TABLE "AuthProvider" RENAME COLUMN provider TO type;
        RAISE NOTICE 'Renamed provider column to type';
    END IF;
    
    -- Add 'config' column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'AuthProvider' AND column_name = 'config') THEN
        ALTER TABLE "AuthProvider" ADD COLUMN config JSONB DEFAULT '{}' NOT NULL;
        RAISE NOTICE 'Added config column';
    END IF;
    
    -- Add 'updatedAt' column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'AuthProvider' AND column_name = 'updatedAt') THEN
        ALTER TABLE "AuthProvider" ADD COLUMN "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL;
        RAISE NOTICE 'Added updatedAt column';
    END IF;
END $$;

-- Update existing entries to have proper config
UPDATE "AuthProvider" 
SET config = '{"provider": "google", "scope": ["openid", "email", "profile"]}'
WHERE type = 'google' AND (config IS NULL OR config = '{}');
EOF

echo ""
echo "Step 3: Verify fixed schema..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\d \"AuthProvider\"" 2>&1 | head -20
echo ""

# Step 4: Show current entries
echo "Step 4: Current AuthProvider entries..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "SELECT type, enabled, config FROM \"AuthProvider\";" 2>&1
echo ""

echo "✅ AuthProvider schema fixed!"
echo ""

# Step 5: Check API container status
echo "Step 5: Checking API container..."
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
if [ ! -z "$API_CONTAINER" ]; then
    echo "API container: $API_CONTAINER"
    echo ""
    echo "API container status:"
    docker inspect $API_CONTAINER --format '{{.State.Status}}'
    echo ""
    echo "Last 20 lines of API logs:"
    docker logs $API_CONTAINER --tail 20 2>&1
    echo ""
    echo "Restarting API container..."
    docker restart $API_CONTAINER > /dev/null 2>&1
    echo "✅ API container restarted"
else
    echo "⚠️  API container not found"
fi

echo ""
echo "===================================================="
echo "Done! Next steps:"
echo "1. Wait 30 seconds for API to start"
echo "2. Test: https://communication-api.caramelme.com/health"
echo "3. Visit: https://communication-dashboard.caramelme.com/dashboard"
echo "===================================================="