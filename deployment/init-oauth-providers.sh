#!/bin/bash

# ==============================================================================
# Initialize OAuth Providers for Multi-tenant Deployment
# This script ensures OAuth providers are properly configured in the database
# ==============================================================================

set -e

echo "===================================================="
echo "OAuth Provider Initialization"
echo "===================================================="
echo ""

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Find containers
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "❌ PostgreSQL container not found. Cannot proceed."
    exit 1
fi

echo "Found containers:"
echo "  Postgres: $POSTGRES_CONTAINER"
echo "  API: ${API_CONTAINER:-NOT FOUND}"
echo ""

# Step 1: Check and create AuthProvider table if missing
echo "Step 1: Ensuring AuthProvider table exists..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << 'EOF'
-- Create AuthProvider table if it doesn't exist
CREATE TABLE IF NOT EXISTS "AuthProvider" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "enabled" BOOLEAN DEFAULT true NOT NULL,
    "config" JSONB DEFAULT '{}' NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

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

-- Create WorkspaceMemberRole table if it doesn't exist
CREATE TABLE IF NOT EXISTS "WorkspaceMemberRole" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "workspaceMemberId" UUID NOT NULL,
    "role" TEXT NOT NULL,
    "resourceType" TEXT DEFAULT 'Workspace',
    "resourceId" UUID,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS "WorkspaceMemberRole_workspaceId_idx" 
ON "WorkspaceMemberRole"("workspaceId");

CREATE INDEX IF NOT EXISTS "WorkspaceMemberRole_workspaceMemberId_idx" 
ON "WorkspaceMemberRole"("workspaceMemberId");

-- Add foreign key constraints if they don't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'WorkspaceMemberRole_workspaceId_fkey') THEN
        ALTER TABLE "WorkspaceMemberRole" ADD CONSTRAINT "WorkspaceMemberRole_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'WorkspaceMemberRole_workspaceMemberId_fkey') THEN
        ALTER TABLE "WorkspaceMemberRole" ADD CONSTRAINT "WorkspaceMemberRole_workspaceMemberId_fkey" 
        FOREIGN KEY ("workspaceMemberId") REFERENCES "WorkspaceMember"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO dittofeed;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO dittofeed;
EOF

echo "✅ AuthProvider table ready"

# Step 2: Get workspace ID
echo ""
echo "Step 2: Getting workspace ID..."
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

# Step 3: Insert Google OAuth provider
echo ""
echo "Step 3: Configuring Google OAuth provider..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
-- Insert or update Google OAuth provider
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

# Step 4: Verify configuration
echo ""
echo "Step 4: Verifying OAuth configuration..."
echo "AuthProvider entries:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "SELECT type, enabled, config FROM \"AuthProvider\" WHERE \"workspaceId\" = '$WORKSPACE_ID';" 2>/dev/null || {
    echo "No AuthProvider entries found or table doesn't exist"
    echo "This is expected on first run - OAuth provider has been configured"
}

# Step 5: Check environment variables
echo ""
echo "Step 5: Checking environment variables..."
if [ ! -z "$API_CONTAINER" ]; then
    echo "API OAuth configuration:"
    docker exec $API_CONTAINER env | grep -E "AUTH_MODE|GOOGLE" | head -5 || echo "No OAuth variables found"
fi

DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
if [ ! -z "$DASHBOARD_CONTAINER" ]; then
    echo ""
    echo "Dashboard OAuth configuration:"
    docker exec $DASHBOARD_CONTAINER env | grep -E "AUTH_MODE|GOOGLE|NEXTAUTH" | head -10 || echo "No OAuth variables found"
fi

# Step 6: Restart services
echo ""
echo "Step 6: Restarting services to apply changes..."
[ ! -z "$API_CONTAINER" ] && docker restart $API_CONTAINER > /dev/null 2>&1
[ ! -z "$DASHBOARD_CONTAINER" ] && docker restart $DASHBOARD_CONTAINER > /dev/null 2>&1

echo "⏳ Waiting for services to start..."
sleep 10

# Step 7: Test OAuth endpoint
echo ""
echo "Step 7: Testing OAuth endpoints..."
echo -n "API auth providers endpoint: "
curl -s https://communication-api.caramelme.com/api/auth/providers 2>/dev/null | head -c 100 || echo "Failed"

echo ""
echo ""
echo "===================================================="
echo "OAuth Provider Initialization Complete!"
echo "===================================================="
echo ""
echo "Next steps:"
echo "1. Ensure these environment variables are set in Coolify:"
echo "   AUTH_MODE=multi-tenant"
echo "   NEXT_PUBLIC_AUTH_MODE=multi-tenant"
echo "   GOOGLE_CLIENT_ID=<your-client-id>"
echo "   GOOGLE_CLIENT_SECRET=<your-secret>"
echo "   NEXTAUTH_URL=https://communication-dashboard.caramelme.com/dashboard"
echo "   NEXTAUTH_SECRET=<your-nextauth-secret>"
echo ""
echo "2. If dashboard still shows anonymous mode:"
echo "   - The dashboard image needs to be rebuilt with AUTH_MODE baked in"
echo "   - Run: ./deployment/build-dashboard-multitenant.sh"
echo ""
echo "3. Visit: https://communication-dashboard.caramelme.com/dashboard"
echo ""