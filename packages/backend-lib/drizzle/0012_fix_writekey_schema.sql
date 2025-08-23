-- Fix WriteKey table schema to match application expectations
-- The 'name' column was incorrectly added but is not used by the application
-- The name is stored in the related Secret table instead

-- Drop the incorrect unique constraint if it exists
DROP INDEX IF EXISTS "WriteKey_workspaceId_name_key";

-- Drop the unused name column if it exists
ALTER TABLE "WriteKey" DROP COLUMN IF EXISTS "name";

-- Create the correct unique index for WriteKey
CREATE UNIQUE INDEX IF NOT EXISTS "WriteKey_workspaceId_secretId_key" 
  ON "WriteKey" ("workspaceId", "secretId");