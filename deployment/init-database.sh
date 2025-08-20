#!/bin/bash
# Initialize Dittofeed database schema manually
# Run this on the server where Docker containers are running

echo "=================================================="
echo "🚀 Initializing Dittofeed Database"
echo "=================================================="
echo ""

# Get container IDs
POSTGRES_CONTAINER=$(docker ps | grep postgres | awk '{print $1}')
API_CONTAINER=$(docker ps | grep "api-" | awk '{print $1}')

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "❌ Error: PostgreSQL container not found"
    exit 1
fi

if [ -z "$API_CONTAINER" ]; then
    echo "❌ Error: API container not found"
    exit 1
fi

echo "✅ Found PostgreSQL container: $POSTGRES_CONTAINER"
echo "✅ Found API container: $API_CONTAINER"
echo ""

# Create temporary SQL file
echo "📝 Creating database schema..."
cat > /tmp/dittofeed-schema.sql << 'EOF'
-- Dittofeed Database Schema
-- Minimal schema to get the application running

-- Drop existing types if they exist (for re-runs)
DROP TYPE IF EXISTS "ComputedPropertyType" CASCADE;
DROP TYPE IF EXISTS "DBBroadcastStatus" CASCADE;
DROP TYPE IF EXISTS "DBChannelType" CASCADE;
DROP TYPE IF EXISTS "DBCompletionStatus" CASCADE;
DROP TYPE IF EXISTS "DBResourceType" CASCADE;
DROP TYPE IF EXISTS "DBRoleType" CASCADE;
DROP TYPE IF EXISTS "DBSubscriptionGroupType" CASCADE;
DROP TYPE IF EXISTS "WorkspaceStatus" CASCADE;
DROP TYPE IF EXISTS "WorkspaceType" CASCADE;

-- Create enums
CREATE TYPE "ComputedPropertyType" AS ENUM ('Segment', 'UserProperty');
CREATE TYPE "DBBroadcastStatus" AS ENUM ('NotStarted', 'InProgress', 'Triggered');
CREATE TYPE "DBChannelType" AS ENUM ('Email', 'MobilePush', 'Sms', 'Webhook');
CREATE TYPE "DBCompletionStatus" AS ENUM ('NotStarted', 'InProgress', 'Successful', 'Failed');
CREATE TYPE "DBResourceType" AS ENUM ('Declarative', 'Internal');
CREATE TYPE "DBRoleType" AS ENUM ('Admin', 'WorkspaceManager', 'Author', 'Viewer');
CREATE TYPE "DBSubscriptionGroupType" AS ENUM ('OptIn', 'OptOut');
CREATE TYPE "WorkspaceStatus" AS ENUM ('Active', 'Tombstoned', 'Paused');
CREATE TYPE "WorkspaceType" AS ENUM ('Root', 'Child', 'Parent');

-- Create Workspace table
CREATE TABLE IF NOT EXISTS "Workspace" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "name" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "domain" TEXT,
    "status" "WorkspaceStatus" DEFAULT 'Active' NOT NULL,
    "type" "WorkspaceType" DEFAULT 'Root' NOT NULL,
    "parentWorkspaceId" UUID,
    "tenantId" TEXT
);

-- Create WorkspaceMember table
CREATE TABLE IF NOT EXISTS "WorkspaceMember" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "email" TEXT NOT NULL,
    "role" "DBRoleType" DEFAULT 'Author' NOT NULL,
    "emailVerified" BOOLEAN DEFAULT false NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create Secret table
CREATE TABLE IF NOT EXISTS "Secret" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create UserProperty table
CREATE TABLE IF NOT EXISTS "UserProperty" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "definition" JSONB NOT NULL,
    "definitionUpdatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "exampleValue" TEXT,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create Segment table
CREATE TABLE IF NOT EXISTS "Segment" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "definition" JSONB NOT NULL,
    "definitionUpdatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "resourceType" "DBResourceType" DEFAULT 'Declarative' NOT NULL
);

-- Create MessageTemplate table
CREATE TABLE IF NOT EXISTS "MessageTemplate" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "definition" JSONB,
    "draft" JSONB,
    "definitionUpdatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "resourceType" "DBResourceType" DEFAULT 'Declarative' NOT NULL
);

-- Create WriteKey table
CREATE TABLE IF NOT EXISTS "WriteKey" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "secretId" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create EmailProvider table
CREATE TABLE IF NOT EXISTS "EmailProvider" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "secretId" UUID,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create DefaultEmailProvider table
CREATE TABLE IF NOT EXISTS "DefaultEmailProvider" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "emailProviderId" UUID NOT NULL,
    "fromAddress" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create Journey table
CREATE TABLE IF NOT EXISTS "Journey" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "definition" JSONB,
    "draft" JSONB,
    "definitionUpdatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "resourceType" "DBResourceType" DEFAULT 'Declarative' NOT NULL
);

-- Create SubscriptionGroup table
CREATE TABLE IF NOT EXISTS "SubscriptionGroup" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "channel" "DBChannelType" NOT NULL,
    "type" "DBSubscriptionGroupType" NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create AuthProvider table
CREATE TABLE IF NOT EXISTS "AuthProvider" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "enabled" BOOLEAN DEFAULT true NOT NULL,
    "config" JSONB DEFAULT '{}' NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create ComputedProperty table
CREATE TABLE IF NOT EXISTS "ComputedProperty" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "type" "ComputedPropertyType" NOT NULL,
    "config" JSONB DEFAULT '{}' NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "definitionUpdatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "status" TEXT DEFAULT 'NotStarted' NOT NULL,
    "lastRecomputed" TIMESTAMP(3),
    "exampleValue" TEXT
);

-- Create indexes if they don't exist
CREATE UNIQUE INDEX IF NOT EXISTS "Workspace_name_key" ON "Workspace"("name");
CREATE INDEX IF NOT EXISTS "Workspace_parentWorkspaceId_idx" ON "Workspace"("parentWorkspaceId");
CREATE INDEX IF NOT EXISTS "Workspace_tenantId_idx" ON "Workspace"("tenantId");
CREATE UNIQUE INDEX IF NOT EXISTS "WorkspaceMember_workspaceId_email_key" ON "WorkspaceMember"("workspaceId", "email");
CREATE UNIQUE INDEX IF NOT EXISTS "Secret_workspaceId_name_key" ON "Secret"("workspaceId", "name");
CREATE UNIQUE INDEX IF NOT EXISTS "UserProperty_workspaceId_name_key" ON "UserProperty"("workspaceId", "name");
CREATE UNIQUE INDEX IF NOT EXISTS "Segment_workspaceId_name_key" ON "Segment"("workspaceId", "name");
CREATE UNIQUE INDEX IF NOT EXISTS "MessageTemplate_workspaceId_name_key" ON "MessageTemplate"("workspaceId", "name");
CREATE UNIQUE INDEX IF NOT EXISTS "WriteKey_workspaceId_name_key" ON "WriteKey"("workspaceId", "name");
CREATE UNIQUE INDEX IF NOT EXISTS "EmailProvider_workspaceId_type_key" ON "EmailProvider"("workspaceId", "type");
CREATE UNIQUE INDEX IF NOT EXISTS "DefaultEmailProvider_workspaceId_key" ON "DefaultEmailProvider"("workspaceId");
CREATE UNIQUE INDEX IF NOT EXISTS "Journey_workspaceId_name_key" ON "Journey"("workspaceId", "name");
CREATE UNIQUE INDEX IF NOT EXISTS "SubscriptionGroup_workspaceId_name_key" ON "SubscriptionGroup"("workspaceId", "name");
CREATE UNIQUE INDEX IF NOT EXISTS "ComputedProperty_workspaceId_name_key" ON "ComputedProperty"("workspaceId", "name");
CREATE UNIQUE INDEX IF NOT EXISTS "AuthProvider_workspaceId_type_key" ON "AuthProvider"("workspaceId", "type");

-- Add foreign key constraints if they don't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Workspace_parentWorkspaceId_fkey') THEN
        ALTER TABLE "Workspace" ADD CONSTRAINT "Workspace_parentWorkspaceId_fkey" 
        FOREIGN KEY ("parentWorkspaceId") REFERENCES "Workspace"("id") ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'WorkspaceMember_workspaceId_fkey') THEN
        ALTER TABLE "WorkspaceMember" ADD CONSTRAINT "WorkspaceMember_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Secret_workspaceId_fkey') THEN
        ALTER TABLE "Secret" ADD CONSTRAINT "Secret_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'UserProperty_workspaceId_fkey') THEN
        ALTER TABLE "UserProperty" ADD CONSTRAINT "UserProperty_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Segment_workspaceId_fkey') THEN
        ALTER TABLE "Segment" ADD CONSTRAINT "Segment_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'MessageTemplate_workspaceId_fkey') THEN
        ALTER TABLE "MessageTemplate" ADD CONSTRAINT "MessageTemplate_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'WriteKey_workspaceId_fkey') THEN
        ALTER TABLE "WriteKey" ADD CONSTRAINT "WriteKey_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'WriteKey_secretId_fkey') THEN
        ALTER TABLE "WriteKey" ADD CONSTRAINT "WriteKey_secretId_fkey" 
        FOREIGN KEY ("secretId") REFERENCES "Secret"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'EmailProvider_workspaceId_fkey') THEN
        ALTER TABLE "EmailProvider" ADD CONSTRAINT "EmailProvider_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'EmailProvider_secretId_fkey') THEN
        ALTER TABLE "EmailProvider" ADD CONSTRAINT "EmailProvider_secretId_fkey" 
        FOREIGN KEY ("secretId") REFERENCES "Secret"("id") ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'DefaultEmailProvider_workspaceId_fkey') THEN
        ALTER TABLE "DefaultEmailProvider" ADD CONSTRAINT "DefaultEmailProvider_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'DefaultEmailProvider_emailProviderId_fkey') THEN
        ALTER TABLE "DefaultEmailProvider" ADD CONSTRAINT "DefaultEmailProvider_emailProviderId_fkey" 
        FOREIGN KEY ("emailProviderId") REFERENCES "EmailProvider"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Journey_workspaceId_fkey') THEN
        ALTER TABLE "Journey" ADD CONSTRAINT "Journey_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'SubscriptionGroup_workspaceId_fkey') THEN
        ALTER TABLE "SubscriptionGroup" ADD CONSTRAINT "SubscriptionGroup_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ComputedProperty_workspaceId_fkey') THEN
        ALTER TABLE "ComputedProperty" ADD CONSTRAINT "ComputedProperty_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'AuthProvider_workspaceId_fkey') THEN
        ALTER TABLE "AuthProvider" ADD CONSTRAINT "AuthProvider_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO dittofeed;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO dittofeed;
EOF

# Apply schema to database
echo "🔨 Applying schema to database..."
docker exec -i $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed < /tmp/dittofeed-schema.sql

if [ $? -eq 0 ]; then
    echo "✅ Schema created successfully"
else
    echo "❌ Failed to create schema"
    exit 1
fi

# Check tables
echo ""
echo "📊 Checking created tables..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\dt"

# Run bootstrap to populate initial data
echo ""
echo "🚀 Running bootstrap to populate initial data..."
docker exec $API_CONTAINER sh -c "cd /service && node packages/backend-lib/dist/src/bootstrap.js"

if [ $? -eq 0 ]; then
    echo "✅ Bootstrap completed successfully"
else
    echo "⚠️  Bootstrap may have encountered issues"
fi

# Restart services
echo ""
echo "🔄 Restarting services..."
docker restart $API_CONTAINER
DASHBOARD_CONTAINER=$(docker ps | grep "dashboard-" | awk '{print $1}')
if [ ! -z "$DASHBOARD_CONTAINER" ]; then
    docker restart $DASHBOARD_CONTAINER
fi

echo ""
echo "⏳ Waiting for services to start..."
sleep 10

# Test endpoints
echo ""
echo "🧪 Testing endpoints..."
echo -n "API Status: "
curl -s https://communication-api.caramelme.com/api >/dev/null 2>&1 && echo "✅ Working" || echo "❌ Failed"
echo -n "Dashboard Status: "
curl -s -I https://communication-dashboard.caramelme.com/ | grep -q "HTTP/2 307" && echo "✅ Working" || echo "❌ Failed"

echo ""
echo "=================================================="
echo "✅ Database initialization complete!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Visit https://communication-dashboard.caramelme.com/"
echo "2. Sign in with Google using the configured OAuth"
echo "3. If you still see errors, check container logs:"
echo "   docker logs $API_CONTAINER"
echo "   docker logs $DASHBOARD_CONTAINER"
echo ""

# Clean up
rm -f /tmp/dittofeed-schema.sql