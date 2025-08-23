-- OAuth Migration Script for Dittofeed Multi-Tenant
-- This script updates the database schema for OAuth authentication support

-- 1. Update WorkspaceMember table to match the new schema
ALTER TABLE "WorkspaceMember" 
  DROP COLUMN IF EXISTS "role",
  ADD COLUMN IF NOT EXISTS "name" TEXT,
  ADD COLUMN IF NOT EXISTS "nickname" TEXT,
  ADD COLUMN IF NOT EXISTS "lastWorkspaceId" UUID;

-- 2. Create WorkspaceMemberRole table for role-based access control
CREATE TABLE IF NOT EXISTS "WorkspaceMemberRole" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "workspaceMemberId" UUID NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'Viewer',
    "resourceType" TEXT,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "WorkspaceMemberRole_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE,
    CONSTRAINT "WorkspaceMemberRole_workspaceMemberId_fkey" 
        FOREIGN KEY ("workspaceMemberId") REFERENCES "WorkspaceMember"("id") ON DELETE CASCADE
);

-- Create unique index to prevent duplicate roles
CREATE UNIQUE INDEX IF NOT EXISTS "WorkspaceMemberRole_workspaceId_workspaceMemberId_key" 
ON "WorkspaceMemberRole"("workspaceId", "workspaceMemberId");

-- 3. Create WorkspaceMembeAccount table for OAuth provider accounts
CREATE TABLE IF NOT EXISTS "WorkspaceMembeAccount" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceMemberId" UUID NOT NULL,
    "provider" TEXT NOT NULL,
    "providerAccountId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "WorkspaceMembeAccount_workspaceMemberId_fkey" 
        FOREIGN KEY ("workspaceMemberId") REFERENCES "WorkspaceMember"("id") ON DELETE CASCADE
);

-- Create unique index to prevent duplicate OAuth accounts
CREATE UNIQUE INDEX IF NOT EXISTS "WorkspaceMembeAccount_provider_providerAccountId_key" 
ON "WorkspaceMembeAccount"("provider", "providerAccountId");

-- 4. Add foreign key constraint for lastWorkspaceId if not exists
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'WorkspaceMember_lastWorkspaceId_fkey') THEN
        ALTER TABLE "WorkspaceMember" ADD CONSTRAINT "WorkspaceMember_lastWorkspaceId_fkey" 
        FOREIGN KEY ("lastWorkspaceId") REFERENCES "Workspace"("id") ON DELETE SET NULL;
    END IF;
END $$;

-- 5. Migrate existing WorkspaceMember roles to WorkspaceMemberRole table
-- Only run if WorkspaceMember has a role column
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'WorkspaceMember' AND column_name = 'role') THEN
        INSERT INTO "WorkspaceMemberRole" ("workspaceId", "workspaceMemberId", "role")
        SELECT "workspaceId", "id", 
               CASE 
                   WHEN "role" = 'Admin' THEN 'Admin'
                   WHEN "role" = 'WorkspaceManager' THEN 'Editor'
                   WHEN "role" = 'Author' THEN 'Editor'
                   WHEN "role" = 'Viewer' THEN 'Viewer'
                   ELSE 'Viewer'
               END
        FROM "WorkspaceMember"
        WHERE "workspaceId" IS NOT NULL
        ON CONFLICT ("workspaceId", "workspaceMemberId") DO NOTHING;
    END IF;
END $$;

-- 6. Create AdminApiKey table if not exists
CREATE TABLE IF NOT EXISTS "AdminApiKey" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "secretId" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT "AdminApiKey_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE,
    CONSTRAINT "AdminApiKey_secretId_fkey" 
        FOREIGN KEY ("secretId") REFERENCES "Secret"("id") ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS "AdminApiKey_workspaceId_name_key" 
ON "AdminApiKey"("workspaceId", "name");

-- 7. Update Workspace table to ensure proper multi-tenant fields
ALTER TABLE "Workspace" 
  ADD COLUMN IF NOT EXISTS "externalId" TEXT;

CREATE INDEX IF NOT EXISTS "Workspace_externalId_idx" ON "Workspace"("externalId");
CREATE INDEX IF NOT EXISTS "Workspace_domain_idx" ON "Workspace"("domain");

-- 8. Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO dittofeed;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO dittofeed;

-- 9. Ensure required unique indexes exist for OAuth token and integration operations
-- These indexes are critical for HubSpot OAuth integration upsert operations

-- Create unique index on OauthToken if it doesn't exist
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'OauthToken_workspaceId_name_key') THEN
        CREATE UNIQUE INDEX "OauthToken_workspaceId_name_key" ON "OauthToken" USING btree ("workspaceId" uuid_ops, "name" text_ops);
        RAISE NOTICE 'Created unique index: OauthToken_workspaceId_name_key';
    ELSE
        RAISE NOTICE 'Index already exists: OauthToken_workspaceId_name_key';
    END IF;
END $$;

-- Create unique index on Integration if it doesn't exist
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'Integration_workspaceId_name_key') THEN
        CREATE UNIQUE INDEX "Integration_workspaceId_name_key" ON "Integration" USING btree ("workspaceId" uuid_ops, "name" text_ops);
        RAISE NOTICE 'Created unique index: Integration_workspaceId_name_key';
    ELSE
        RAISE NOTICE 'Index already exists: Integration_workspaceId_name_key';
    END IF;
END $$;

-- Analyze tables to update query planner statistics
ANALYZE "OauthToken";
ANALYZE "Integration";

-- 10. Display migration results
SELECT 'OAuth Migration Complete' AS status;
SELECT COUNT(*) AS workspace_count FROM "Workspace";
SELECT COUNT(*) AS member_count FROM "WorkspaceMember";
SELECT COUNT(*) AS role_count FROM "WorkspaceMemberRole";
SELECT COUNT(*) AS oauth_account_count FROM "WorkspaceMembeAccount";