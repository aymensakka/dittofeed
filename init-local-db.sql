-- Create basic tables for Dittofeed multi-tenant setup
-- This is a minimal setup to get started

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create Workspace table
CREATE TABLE IF NOT EXISTS "Workspace" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL,
    type TEXT NOT NULL DEFAULT 'Root',
    status TEXT NOT NULL DEFAULT 'Active',
    domain TEXT,
    "externalId" TEXT,
    "parentWorkspaceId" UUID REFERENCES "Workspace"(id),
    "createdAt" TIMESTAMP NOT NULL DEFAULT NOW(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Create AuthProvider table
CREATE TABLE IF NOT EXISTS "AuthProvider" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "workspaceId" UUID NOT NULL REFERENCES "Workspace"(id),
    "type" TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT true,
    config JSONB NOT NULL DEFAULT '{}',
    "createdAt" TIMESTAMP NOT NULL DEFAULT NOW(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Create WorkspaceMember table
CREATE TABLE IF NOT EXISTS "WorkspaceMember" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "workspaceId" UUID NOT NULL REFERENCES "Workspace"(id),
    email TEXT NOT NULL,
    name TEXT,
    nickname TEXT,
    "lastWorkspaceId" UUID REFERENCES "Workspace"(id),
    "emailVerified" BOOLEAN DEFAULT false,
    "createdAt" TIMESTAMP NOT NULL DEFAULT NOW(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE("workspaceId", email)
);

-- Create WorkspaceMemberRole table
CREATE TABLE IF NOT EXISTS "WorkspaceMemberRole" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "workspaceId" UUID NOT NULL REFERENCES "Workspace"(id),
    "workspaceMemberId" UUID NOT NULL REFERENCES "WorkspaceMember"(id),
    role TEXT NOT NULL,
    "resourceType" TEXT,
    "createdAt" TIMESTAMP NOT NULL DEFAULT NOW(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Create UserProperty table
CREATE TABLE IF NOT EXISTS "UserProperty" (
    id TEXT PRIMARY KEY,
    "workspaceId" UUID NOT NULL REFERENCES "Workspace"(id),
    name TEXT NOT NULL,
    definition JSONB NOT NULL,
    "createdAt" TIMESTAMP NOT NULL DEFAULT NOW(),
    "updatedAt" TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE("workspaceId", name)
);

-- Insert default workspace
INSERT INTO "Workspace" (name, type, status, domain)
VALUES ('localhost', 'Root', 'Active', 'localhost')
ON CONFLICT (name) DO UPDATE SET domain = EXCLUDED.domain;

-- Get workspace ID for further inserts
DO $$
DECLARE
    workspace_id UUID;
BEGIN
    SELECT id INTO workspace_id FROM "Workspace" WHERE name = 'localhost' LIMIT 1;
    
    -- Insert OAuth provider
    DELETE FROM "AuthProvider" WHERE "workspaceId" = workspace_id;
    
    INSERT INTO "AuthProvider" ("workspaceId", "type", enabled, config)
    VALUES (
        workspace_id,
        'google',
        true,
        '{"provider": "google", "scope": ["openid", "email", "profile"]}'::jsonb
    );
    
    -- Insert default user properties
    INSERT INTO "UserProperty" (id, "workspaceId", name, definition)
    VALUES 
        (gen_random_uuid()::text, workspace_id, 'email', '{"type": "Trait"}'::jsonb),
        (gen_random_uuid()::text, workspace_id, 'firstName', '{"type": "Trait"}'::jsonb),
        (gen_random_uuid()::text, workspace_id, 'lastName', '{"type": "Trait"}'::jsonb),
        (gen_random_uuid()::text, workspace_id, 'phone', '{"type": "Trait"}'::jsonb),
        (gen_random_uuid()::text, workspace_id, 'id', '{"type": "Id"}'::jsonb),
        (gen_random_uuid()::text, workspace_id, 'anonymousId', '{"type": "AnonymousId"}'::jsonb)
    ON CONFLICT ("workspaceId", name) DO NOTHING;
END $$;