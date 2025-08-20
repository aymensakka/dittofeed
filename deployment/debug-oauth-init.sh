#!/bin/bash

# ==============================================================================
# Debug OAuth Initialization Issues
# ==============================================================================

set -e

echo "===================================================="
echo "Debug OAuth Initialization"
echo "===================================================="
echo ""

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Find containers
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)

echo "Containers:"
echo "  Postgres: $POSTGRES_CONTAINER"
echo "  API: $API_CONTAINER"
echo ""

# Check if AuthProvider table exists
echo "1. Checking if AuthProvider table exists..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\dt \"AuthProvider\"" 2>&1 || echo "Table doesn't exist"
echo ""

# Check workspace
echo "2. Checking workspace..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM \"Workspace\";" 2>&1
echo ""

# Try to query AuthProvider with error handling
echo "3. Checking AuthProvider entries (with verbose error)..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT * FROM \"AuthProvider\";" 2>&1 || {
    echo "Failed to query AuthProvider table"
    echo ""
    echo "Trying to create the table..."
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << 'EOF'
CREATE TABLE IF NOT EXISTS "AuthProvider" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL REFERENCES "Workspace"("id"),
    "type" TEXT NOT NULL,
    "enabled" BOOLEAN DEFAULT true NOT NULL,
    "config" JSONB DEFAULT '{}' NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "AuthProvider_workspaceId_type_key" ON "AuthProvider"("workspaceId", "type");
EOF
}
echo ""

# Get workspace ID and insert OAuth provider
echo "4. Setting up OAuth provider..."
WORKSPACE_ID=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT id FROM \"Workspace\" LIMIT 1;" 2>/dev/null | tr -d ' \n')
echo "Workspace ID: $WORKSPACE_ID"

if [ ! -z "$WORKSPACE_ID" ]; then
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
INSERT INTO "AuthProvider" ("workspaceId", "type", "enabled", "config")
VALUES ('$WORKSPACE_ID', 'google', true, '{"provider": "google"}')
ON CONFLICT ("workspaceId", "type") DO UPDATE SET enabled = true;
EOF
    echo "OAuth provider inserted/updated"
fi
echo ""

# Final check
echo "5. Final verification..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT type, enabled FROM \"AuthProvider\";" 2>&1 || echo "Still no AuthProvider entries"
echo ""

echo "Done!"