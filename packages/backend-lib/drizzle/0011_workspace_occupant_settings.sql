-- Create WorkspaceOccupantSetting table for multi-tenant workspace member settings
CREATE TABLE IF NOT EXISTS "WorkspaceOccupantSetting" (
  "workspaceId" UUID NOT NULL,
  "name" TEXT NOT NULL,
  "workspaceOccupantId" TEXT NOT NULL,
  "occupantType" "DBWorkspaceOccupantType" NOT NULL,
  "config" JSONB,
  "secretId" UUID,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT NOW(),
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT NOW()
);

-- Add unique constraint for workspace occupant settings
ALTER TABLE "WorkspaceOccupantSetting" 
  ADD CONSTRAINT "WorkspaceOccupantSetting_workspaceId_occupantId_name_key" 
  UNIQUE ("workspaceId", "workspaceOccupantId", "name");

-- Add foreign key constraints
ALTER TABLE "WorkspaceOccupantSetting"
  ADD CONSTRAINT "WorkspaceOccupantSetting_workspaceId_fkey" 
  FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE;

ALTER TABLE "WorkspaceOccupantSetting"
  ADD CONSTRAINT "WorkspaceOccupantSetting_secretId_fkey"
  FOREIGN KEY ("secretId") REFERENCES "Secret"("id") ON DELETE SET NULL;

-- Add unique constraint for Secret table (workspace + name)
CREATE UNIQUE INDEX IF NOT EXISTS "Secret_workspaceId_name_key" 
  ON "Secret" ("workspaceId", "name");

-- Enable Row-Level Security for WorkspaceOccupantSetting
ALTER TABLE "WorkspaceOccupantSetting" ENABLE ROW LEVEL SECURITY;

-- Create workspace isolation policy for WorkspaceOccupantSetting
CREATE POLICY "workspace_occupant_setting_workspace_isolation" ON "WorkspaceOccupantSetting"
  USING ("workspaceId" = current_setting('app.current_workspace_id', true)::uuid);

-- Grant necessary permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON "WorkspaceOccupantSetting" TO PUBLIC;