-- Add unique constraint on Segment table for workspaceId and name
CREATE UNIQUE INDEX IF NOT EXISTS "Segment_workspaceId_name_unique" 
ON "Segment" ("workspaceId", "name");