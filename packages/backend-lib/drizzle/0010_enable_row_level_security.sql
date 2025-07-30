-- Enable Row-Level Security (RLS) for enterprise-grade tenant isolation
-- This provides defense-in-depth security by enforcing workspace isolation at the database level

-- Enable RLS on critical tenant-scoped tables
ALTER TABLE "Segment" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Journey" ENABLE ROW LEVEL SECURITY;  
ALTER TABLE "MessageTemplate" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "EmailTemplate" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Broadcast" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "UserProperty" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "UserPropertyAssignment" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "EmailProvider" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "SubscriptionGroup" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Integration" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Secret" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "WriteKey" ENABLE ROW LEVEL SECURITY;

-- Create workspace isolation policies for each table
-- These policies ensure users can only access data within their workspace context

-- Segment workspace isolation policy
CREATE POLICY "segment_workspace_isolation" ON "Segment"
  USING ("workspaceId" = current_setting('app.current_workspace_id', true)::uuid);

-- Journey workspace isolation policy  
CREATE POLICY "journey_workspace_isolation" ON "Journey"
  USING ("workspaceId" = current_setting('app.current_workspace_id', true)::uuid);

-- MessageTemplate workspace isolation policy
CREATE POLICY "message_template_workspace_isolation" ON "MessageTemplate"
  USING ("workspaceId" = current_setting('app.current_workspace_id', true)::uuid);

-- EmailTemplate workspace isolation policy
CREATE POLICY "email_template_workspace_isolation" ON "EmailTemplate"
  USING ("workspaceId" = current_setting('app.current_workspace_id', true)::uuid);

-- Broadcast workspace isolation policy
CREATE POLICY "broadcast_workspace_isolation" ON "Broadcast"
  USING ("workspaceId" = current_setting('app.current_workspace_id', true)::uuid);

-- UserProperty workspace isolation policy
CREATE POLICY "user_property_workspace_isolation" ON "UserProperty"
  USING ("workspaceId" = current_setting('app.current_workspace_id', true)::uuid);

-- UserPropertyAssignment workspace isolation policy
CREATE POLICY "user_property_assignment_workspace_isolation" ON "UserPropertyAssignment"
  USING ("workspaceId" = current_setting('app.current_workspace_id', true)::uuid);

-- EmailProvider workspace isolation policy
CREATE POLICY "email_provider_workspace_isolation" ON "EmailProvider"
  USING ("workspaceId" = current_setting('app.current_workspace_id', true)::uuid);

-- SubscriptionGroup workspace isolation policy
CREATE POLICY "subscription_group_workspace_isolation" ON "SubscriptionGroup"
  USING ("workspaceId" = current_setting('app.current_workspace_id', true)::uuid);

-- Integration workspace isolation policy
CREATE POLICY "integration_workspace_isolation" ON "Integration"
  USING ("workspaceId" = current_setting('app.current_workspace_id', true)::uuid);

-- Secret workspace isolation policy
CREATE POLICY "secret_workspace_isolation" ON "Secret"
  USING ("workspaceId" = current_setting('app.current_workspace_id', true)::uuid);

-- WriteKey workspace isolation policy  
CREATE POLICY "write_key_workspace_isolation" ON "WriteKey"
  USING ("workspaceId" = current_setting('app.current_workspace_id', true)::uuid);

-- Grant necessary permissions for application users
-- Note: These should be adjusted based on your specific role structure
GRANT SELECT, INSERT, UPDATE, DELETE ON "Segment" TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON "Journey" TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON "MessageTemplate" TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON "EmailTemplate" TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON "Broadcast" TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON "UserProperty" TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON "UserPropertyAssignment" TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON "EmailProvider" TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON "SubscriptionGroup" TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON "Integration" TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON "Secret" TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON "WriteKey" TO PUBLIC;