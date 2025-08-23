-- Schema Consistency Fix for HubSpot OAuth Integration
-- This script ensures the database schema is consistent with the code definitions
-- Run this after initial database setup to fix any missing indexes or constraints

-- Fix 1: Ensure unique indexes exist for OAuth operations
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'OauthToken_workspaceId_name_key') THEN
        CREATE UNIQUE INDEX "OauthToken_workspaceId_name_key" ON "OauthToken" USING btree ("workspaceId" uuid_ops, "name" text_ops);
        RAISE NOTICE 'Fixed: Created unique index OauthToken_workspaceId_name_key';
    ELSE
        RAISE NOTICE 'OK: OauthToken_workspaceId_name_key index exists';
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'Integration_workspaceId_name_key') THEN
        CREATE UNIQUE INDEX "Integration_workspaceId_name_key" ON "Integration" USING btree ("workspaceId" uuid_ops, "name" text_ops);
        RAISE NOTICE 'Fixed: Created unique index Integration_workspaceId_name_key';
    ELSE
        RAISE NOTICE 'OK: Integration_workspaceId_name_key index exists';
    END IF;
END $$;

-- Fix 2: Verify OAuth-related tables have correct foreign key constraints
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'OauthToken_workspaceId_fkey') THEN
        ALTER TABLE "OauthToken" ADD CONSTRAINT "OauthToken_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "public"."Workspace"("id") ON DELETE cascade ON UPDATE cascade;
        RAISE NOTICE 'Fixed: Added OauthToken workspace foreign key';
    ELSE
        RAISE NOTICE 'OK: OauthToken workspace foreign key exists';
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'Integration_workspaceId_fkey') THEN
        ALTER TABLE "Integration" ADD CONSTRAINT "Integration_workspaceId_fkey" 
        FOREIGN KEY ("workspaceId") REFERENCES "public"."Workspace"("id") ON DELETE cascade ON UPDATE cascade;
        RAISE NOTICE 'Fixed: Added Integration workspace foreign key';
    ELSE
        RAISE NOTICE 'OK: Integration workspace foreign key exists';
    END IF;
END $$;

-- Fix 3: Verify workspace member OAuth account constraints
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'WorkspaceMembeAccount_workspaceMemberId_fkey') THEN
        ALTER TABLE "WorkspaceMembeAccount" ADD CONSTRAINT "WorkspaceMembeAccount_workspaceMemberId_fkey" 
        FOREIGN KEY ("workspaceMemberId") REFERENCES "public"."WorkspaceMember"("id") ON DELETE cascade ON UPDATE cascade;
        RAISE NOTICE 'Fixed: Added WorkspaceMembeAccount member foreign key';
    ELSE
        RAISE NOTICE 'OK: WorkspaceMembeAccount member foreign key exists';
    END IF;
END $$;

-- Fix 4: Ensure provider account ID uniqueness for OAuth accounts
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'WorkspaceMembeAccount_provider_providerAccountId_key') THEN
        CREATE UNIQUE INDEX "WorkspaceMembeAccount_provider_providerAccountId_key" ON "WorkspaceMembeAccount" USING btree ("provider" text_ops, "providerAccountId" text_ops);
        RAISE NOTICE 'Fixed: Created unique index for OAuth provider accounts';
    ELSE
        RAISE NOTICE 'OK: OAuth provider account unique index exists';
    END IF;
END $$;

-- Fix 5: Update table statistics for query optimization
ANALYZE "OauthToken";
ANALYZE "Integration";
ANALYZE "WorkspaceMembeAccount";

-- Display summary
SELECT 'Database schema consistency check completed' AS status;
SELECT 
    schemaname,
    tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes
FROM pg_stat_user_tables 
WHERE tablename IN ('OauthToken', 'Integration', 'WorkspaceMembeAccount')
ORDER BY tablename;