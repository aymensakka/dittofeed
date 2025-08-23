-- Migration: Add missing unique indexes for HubSpot OAuth integration
-- These indexes are required for upsert operations on OauthToken and Integration tables

-- Create unique index on OauthToken if it doesn't exist
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'OauthToken_workspaceId_name_key') THEN
        CREATE UNIQUE INDEX "OauthToken_workspaceId_name_key" ON "OauthToken" USING btree ("workspaceId" uuid_ops, "name" text_ops);
    END IF;
END $$;

-- Create unique index on Integration if it doesn't exist
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'Integration_workspaceId_name_key') THEN
        CREATE UNIQUE INDEX "Integration_workspaceId_name_key" ON "Integration" USING btree ("workspaceId" uuid_ops, "name" text_ops);
    END IF;
END $$;

-- Analyze tables to update query planner statistics
ANALYZE "OauthToken";
ANALYZE "Integration";