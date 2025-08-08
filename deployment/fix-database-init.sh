#!/bin/bash
# Quick fix script to initialize Dittofeed database

echo "🔧 Fixing Dittofeed Database Initialization"
echo ""

# Get container IDs
POSTGRES_CONTAINER=$(docker ps | grep postgres | awk '{print $1}')
API_CONTAINER=$(docker ps | grep "api-" | awk '{print $1}')

echo "Step 1: Creating minimal schema for bootstrap"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << 'EOF'
-- Create basic enums needed for bootstrap
CREATE TYPE "WorkspaceType" AS ENUM ('Root', 'Child', 'Parent');
CREATE TYPE "WorkspaceStatus" AS ENUM ('Active', 'Tombstoned', 'Paused');
CREATE TYPE "DBRoleType" AS ENUM ('Admin', 'WorkspaceManager', 'Author', 'Viewer');

-- Create Workspace table (minimal)
CREATE TABLE "Workspace" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "name" TEXT NOT NULL UNIQUE,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "type" "WorkspaceType" DEFAULT 'Root' NOT NULL,
    "status" "WorkspaceStatus" DEFAULT 'Active' NOT NULL
);

-- Create WorkspaceMember table (minimal)
CREATE TABLE "WorkspaceMember" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL REFERENCES "Workspace"("id"),
    "email" TEXT NOT NULL,
    "role" "DBRoleType" DEFAULT 'Admin' NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create Secret table (minimal)
CREATE TABLE "Secret" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL REFERENCES "Workspace"("id"),
    "name" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create WriteKey table (minimal)
CREATE TABLE "WriteKey" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL REFERENCES "Workspace"("id"),
    "name" TEXT NOT NULL,
    "secretId" UUID NOT NULL REFERENCES "Secret"("id"),
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

GRANT ALL ON ALL TABLES IN SCHEMA public TO dittofeed;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO dittofeed;
EOF

echo "Step 2: Running bootstrap"
docker exec $API_CONTAINER sh -c "cd /service && node packages/backend-lib/dist/src/bootstrap.js"

echo "Step 3: Checking results"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\dt"

echo "Step 4: Restarting services"
docker restart $API_CONTAINER
docker restart $(docker ps | grep "dashboard-" | awk '{print $1}')

echo "Done! Check https://communication-dashboard.caramelme.com in 30 seconds"