-- Additional tenant-aware composite indexes for multitenancy performance enhancement
-- These indexes optimize workspace-scoped queries for better performance

-- MessageTemplate table needs performance index similar to Segment and Journey
CREATE INDEX CONCURRENTLY "idx_message_template_workspace_perf" ON "MessageTemplate" USING btree ("workspaceId" uuid_ops, "updatedAt" timestamp_ops);

-- Broadcast table performance index for workspace queries
CREATE INDEX CONCURRENTLY "idx_broadcast_workspace_perf" ON "Broadcast" USING btree ("workspaceId" uuid_ops, "triggeredAt" timestamp_ops);

-- UserPropertyAssignment index for efficient user property lookups by workspace
CREATE INDEX CONCURRENTLY "idx_user_property_assignment_workspace_user" ON "UserPropertyAssignment" USING btree ("workspaceId" uuid_ops, "userId" text_ops);

-- EmailProvider workspace performance index
CREATE INDEX CONCURRENTLY "idx_email_provider_workspace_type" ON "EmailProvider" USING btree ("workspaceId" uuid_ops, "type" text_ops);

-- Secret table workspace index for API key lookups
CREATE INDEX CONCURRENTLY "idx_secret_workspace_name" ON "Secret" USING btree ("workspaceId" uuid_ops, "name" text_ops);

-- Integration table workspace performance index
CREATE INDEX CONCURRENTLY "idx_integration_workspace_type" ON "Integration" USING btree ("workspaceId" uuid_ops, "type" text_ops);

-- SegmentAssignment table index for user segment membership queries
CREATE INDEX CONCURRENTLY "idx_segment_assignment_workspace_segment" ON "SegmentAssignment" USING btree ("workspaceId" uuid_ops, "segmentId" uuid_ops, "inSegment" bool_ops);

-- Analyze tables to update query planner statistics after index creation
ANALYZE "MessageTemplate";
ANALYZE "Broadcast";
ANALYZE "UserPropertyAssignment";
ANALYZE "EmailProvider";
ANALYZE "Secret";
ANALYZE "Integration";
ANALYZE "SegmentAssignment";