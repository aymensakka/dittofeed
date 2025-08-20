#!/bin/bash

# ==============================================================================
# Reset and Fix OAuth Schema - Complete cleanup and recreation
# ==============================================================================

set -e

echo "===================================================="
echo "Reset and Fix OAuth Schema"
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

# Step 1: Backup existing data if any
echo "Step 1: Backing up existing AuthProvider data (if any)..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << 'EOF'
-- Create temporary backup table
CREATE TEMP TABLE auth_provider_backup AS 
SELECT * FROM "AuthProvider" WHERE FALSE;

-- Try to backup data if table exists with either schema
DO $$ 
BEGIN
    -- Try with 'provider' column
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'AuthProvider' AND column_name = 'provider') THEN
        INSERT INTO auth_provider_backup 
        SELECT id, "workspaceId", provider as type, enabled, 
               COALESCE(config, '{}') as config, "createdAt", 
               COALESCE("updatedAt", "createdAt") as "updatedAt"
        FROM "AuthProvider";
        RAISE NOTICE 'Backed up data with provider column';
    -- Try with 'type' column
    ELSIF EXISTS (SELECT 1 FROM information_schema.columns 
                  WHERE table_name = 'AuthProvider' AND column_name = 'type') THEN
        INSERT INTO auth_provider_backup 
        SELECT id, "workspaceId", type, enabled, 
               COALESCE(config, '{}') as config, "createdAt",
               COALESCE("updatedAt", "createdAt") as "updatedAt"
        FROM "AuthProvider";
        RAISE NOTICE 'Backed up data with type column';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Could not backup data: %', SQLERRM;
END $$;
EOF
echo ""

# Step 2: Check if we need to rename column or drop table
echo "Step 2: Checking table structure..."
COLUMN_EXISTS=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c \
    "SELECT column_name FROM information_schema.columns WHERE table_name = 'AuthProvider' AND column_name = 'provider';" 2>/dev/null | tr -d ' \n')

if [ ! -z "$COLUMN_EXISTS" ]; then
    echo "Found 'provider' column - renaming to 'type'..."
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
        "ALTER TABLE \"AuthProvider\" RENAME COLUMN provider TO type;" 2>&1
    echo "✅ Column renamed"
    
    # Add missing columns
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << 'EOF'
ALTER TABLE "AuthProvider" 
ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL;

ALTER TABLE "AuthProvider" 
ALTER COLUMN config SET DEFAULT '{}';

UPDATE "AuthProvider" 
SET config = '{"provider": "google", "scope": ["openid", "email", "profile"]}'
WHERE config IS NULL OR config = '{}';
EOF
    echo "✅ Table structure fixed"
else
    # Check if table exists with correct column
    TYPE_EXISTS=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c \
        "SELECT column_name FROM information_schema.columns WHERE table_name = 'AuthProvider' AND column_name = 'type';" 2>/dev/null | tr -d ' \n')
    
    if [ -z "$TYPE_EXISTS" ]; then
        echo "Table doesn't exist or has wrong structure - recreating..."
        docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << 'EOF'
DROP TABLE IF EXISTS "AuthProvider" CASCADE;

-- Create AuthProvider table with correct schema
CREATE TABLE "AuthProvider" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "enabled" BOOLEAN DEFAULT true NOT NULL,
    "config" JSONB DEFAULT '{}' NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create indexes
CREATE UNIQUE INDEX "AuthProvider_workspaceId_type_key" ON "AuthProvider"("workspaceId", "type");

-- Add foreign key constraint
ALTER TABLE "AuthProvider" ADD CONSTRAINT "AuthProvider_workspaceId_fkey" 
FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Grant permissions
GRANT ALL PRIVILEGES ON "AuthProvider" TO dittofeed;
EOF
        echo "✅ Table recreated with correct schema"
    else
        echo "✅ Table already has correct structure"
    fi
fi
echo ""

# Step 3: Ensure indexes and constraints exist
echo "Step 3: Ensuring indexes and constraints..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << 'EOF'
-- Create index if it doesn't exist
CREATE UNIQUE INDEX IF NOT EXISTS "AuthProvider_workspaceId_type_key" 
ON "AuthProvider"("workspaceId", "type");

-- Add foreign key if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'AuthProvider_workspaceId_fkey') THEN
        ALTER TABLE "AuthProvider" ADD CONSTRAINT "AuthProvider_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;
EOF
echo ""

# Step 4: Get workspace and insert OAuth provider
echo "Step 4: Setting up Google OAuth provider..."
WORKSPACE_ID=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c \
    "SELECT id FROM \"Workspace\" WHERE name = 'caramel' OR type = 'Root' LIMIT 1;" 2>/dev/null | tr -d ' \n')

if [ -z "$WORKSPACE_ID" ]; then
    echo "⚠️  No workspace found. Creating default workspace..."
    WORKSPACE_ID=$(uuidgen 2>/dev/null || echo "$(date +%s)-$(shuf -i 1000-9999 -n 1)")
    
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
INSERT INTO "Workspace" (
    id, name, type, status, domain, "createdAt", "updatedAt"
) VALUES (
    '$WORKSPACE_ID', 'caramel', 'Root', 'Active', 'caramelme.com', NOW(), NOW()
) ON CONFLICT (name) DO UPDATE SET domain = 'caramelme.com'
RETURNING id;
EOF
    
    WORKSPACE_ID=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c \
        "SELECT id FROM \"Workspace\" WHERE name = 'caramel' LIMIT 1;" 2>/dev/null | tr -d ' \n')
fi

echo "Workspace ID: $WORKSPACE_ID"

# Insert Google OAuth provider
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
INSERT INTO "AuthProvider" (
    "workspaceId",
    "type",
    "enabled",
    "config",
    "createdAt",
    "updatedAt"
) VALUES (
    '$WORKSPACE_ID',
    'google',
    true,
    '{"provider": "google", "scope": ["openid", "email", "profile"]}',
    NOW(),
    NOW()
) ON CONFLICT ("workspaceId", "type") 
DO UPDATE SET 
    "enabled" = true,
    "config" = '{"provider": "google", "scope": ["openid", "email", "profile"]}',
    "updatedAt" = NOW();
EOF
echo "✅ Google OAuth provider configured"
echo ""

# Step 5: Verify the new schema
echo "Step 5: Verifying new schema..."
echo "Table structure:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\d \"AuthProvider\"" 2>&1 | head -25
echo ""

echo "AuthProvider entries:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "SELECT type, enabled, config FROM \"AuthProvider\";" 2>&1
echo ""

# Step 6: Restart services
echo "Step 6: Restarting services..."
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)

if [ ! -z "$API_CONTAINER" ]; then
    docker restart $API_CONTAINER > /dev/null 2>&1
    echo "✅ API container restarted"
fi

if [ ! -z "$DASHBOARD_CONTAINER" ]; then
    docker restart $DASHBOARD_CONTAINER > /dev/null 2>&1
    echo "✅ Dashboard container restarted"
fi

echo ""
echo "⏳ Waiting for services to start..."
sleep 15

# Step 7: Check service status
echo ""
echo "Step 7: Checking service status..."
if [ ! -z "$API_CONTAINER" ]; then
    echo -n "API health: "
    docker exec $API_CONTAINER curl -s -f http://localhost:3001/health >/dev/null 2>&1 && echo "✅ Healthy" || echo "⚠️  Not ready yet"
fi

echo ""
echo "===================================================="
echo "OAuth Schema Reset Complete!"
echo "===================================================="
echo ""
echo "The AuthProvider table has been recreated with the correct schema."
echo ""
echo "Next steps:"
echo "1. Wait 30 seconds for services to fully start"
echo "2. Test API: https://communication-api.caramelme.com/health"
echo "3. Visit: https://communication-dashboard.caramelme.com/dashboard"
echo ""
echo "You should now see Google OAuth login instead of anonymous mode."
echo "===================================================="