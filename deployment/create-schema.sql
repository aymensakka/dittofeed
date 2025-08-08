-- Create Dittofeed schema manually
-- This is a temporary solution to initialize the database

-- Create enums
CREATE TYPE "ComputedPropertyType" AS ENUM ('Segment', 'UserProperty');
CREATE TYPE "DBBroadcastStatus" AS ENUM ('NotStarted', 'InProgress', 'Triggered');
CREATE TYPE "DBBroadcastStatusV2" AS ENUM ('Draft', 'Scheduled', 'Running', 'Paused', 'Completed', 'Cancelled', 'Failed');
CREATE TYPE "DBBroadcastVersion" AS ENUM ('V1', 'V2');
CREATE TYPE "DBChannelType" AS ENUM ('Email', 'MobilePush', 'Sms', 'Webhook');
CREATE TYPE "DBCompletionStatus" AS ENUM ('NotStarted', 'InProgress', 'Successful', 'Failed');
CREATE TYPE "DBResourceType" AS ENUM ('Declarative', 'Internal');
CREATE TYPE "DBRoleType" AS ENUM ('Admin', 'WorkspaceManager', 'Author', 'Viewer');
CREATE TYPE "DBSubscriptionGroupType" AS ENUM ('OptIn', 'OptOut');
CREATE TYPE "DBWorkspaceOccupantType" AS ENUM ('WorkspaceMember', 'ChildWorkspaceOccupant');
CREATE TYPE "JourneyStatus" AS ENUM ('NotStarted', 'Running', 'Paused', 'Broadcast');
CREATE TYPE "SegmentStatus" AS ENUM ('NotStarted', 'Running', 'Paused');
CREATE TYPE "UserPropertyStatus" AS ENUM ('NotStarted', 'Running', 'Paused');
CREATE TYPE "WorkspaceStatus" AS ENUM ('Active', 'Tombstoned', 'Paused');
CREATE TYPE "WorkspaceType" AS ENUM ('Root', 'Child', 'Parent');

-- Create Workspace table first (referenced by other tables)
CREATE TABLE "Workspace" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "name" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "domain" TEXT,
    "status" "WorkspaceStatus" DEFAULT 'Active' NOT NULL,
    "type" "WorkspaceType" DEFAULT 'Root' NOT NULL,
    "parentWorkspaceId" UUID,
    "ownerId" TEXT,
    "tenantId" TEXT
);

-- Create WorkspaceMember table
CREATE TABLE "WorkspaceMember" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "email" TEXT NOT NULL,
    "role" "DBRoleType" DEFAULT 'Author' NOT NULL,
    "emailVerified" BOOLEAN DEFAULT false NOT NULL,
    "nickname" TEXT,
    "image" TEXT,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create Secret table
CREATE TABLE "Secret" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create UserProperty table
CREATE TABLE "UserProperty" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "definition" JSONB NOT NULL,
    "definitionUpdatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "exampleValue" TEXT,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "computedPropertyId" UUID
);

-- Create Segment table
CREATE TABLE "Segment" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "definition" JSONB NOT NULL,
    "definitionUpdatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "resourceType" "DBResourceType" DEFAULT 'Declarative' NOT NULL,
    "subscriptionGroupId" UUID
);

-- Create MessageTemplate table
CREATE TABLE "MessageTemplate" (
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
CREATE TABLE "WriteKey" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "secretId" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create EmailProvider table
CREATE TABLE "EmailProvider" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "secretId" UUID,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create DefaultEmailProvider table
CREATE TABLE "DefaultEmailProvider" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "emailProviderId" UUID NOT NULL,
    "fromAddress" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create SmsProvider table
CREATE TABLE "SmsProvider" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "secretId" UUID,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create DefaultSmsProvider table
CREATE TABLE "DefaultSmsProvider" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "smsProviderId" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create Journey table
CREATE TABLE "Journey" (
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
CREATE TABLE "SubscriptionGroup" (
    "id" UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    "workspaceId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "channel" "DBChannelType" NOT NULL,
    "type" "DBSubscriptionGroupType" NOT NULL,
    "createdAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Create ComputedProperty table
CREATE TABLE "ComputedProperty" (
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

-- Create indexes
CREATE UNIQUE INDEX "Workspace_name_key" ON "Workspace"("name");
CREATE INDEX "Workspace_parentWorkspaceId_idx" ON "Workspace"("parentWorkspaceId");
CREATE INDEX "Workspace_tenantId_idx" ON "Workspace"("tenantId");
CREATE UNIQUE INDEX "WorkspaceMember_workspaceId_email_key" ON "WorkspaceMember"("workspaceId", "email");
CREATE UNIQUE INDEX "Secret_workspaceId_name_key" ON "Secret"("workspaceId", "name");
CREATE UNIQUE INDEX "UserProperty_workspaceId_name_key" ON "UserProperty"("workspaceId", "name");
CREATE UNIQUE INDEX "Segment_workspaceId_name_key" ON "Segment"("workspaceId", "name");
CREATE UNIQUE INDEX "MessageTemplate_workspaceId_name_key" ON "MessageTemplate"("workspaceId", "name");
CREATE UNIQUE INDEX "WriteKey_workspaceId_name_key" ON "WriteKey"("workspaceId", "name");
CREATE UNIQUE INDEX "EmailProvider_workspaceId_type_key" ON "EmailProvider"("workspaceId", "type");
CREATE UNIQUE INDEX "DefaultEmailProvider_workspaceId_key" ON "DefaultEmailProvider"("workspaceId");
CREATE UNIQUE INDEX "SmsProvider_workspaceId_type_key" ON "SmsProvider"("workspaceId", "type");
CREATE UNIQUE INDEX "DefaultSmsProvider_workspaceId_key" ON "DefaultSmsProvider"("workspaceId");
CREATE UNIQUE INDEX "Journey_workspaceId_name_key" ON "Journey"("workspaceId", "name");
CREATE UNIQUE INDEX "SubscriptionGroup_workspaceId_name_key" ON "SubscriptionGroup"("workspaceId", "name");
CREATE UNIQUE INDEX "ComputedProperty_workspaceId_name_key" ON "ComputedProperty"("workspaceId", "name");

-- Add foreign key constraints
ALTER TABLE "Workspace" ADD CONSTRAINT "Workspace_parentWorkspaceId_fkey" FOREIGN KEY ("parentWorkspaceId") REFERENCES "Workspace"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "WorkspaceMember" ADD CONSTRAINT "WorkspaceMember_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "Secret" ADD CONSTRAINT "Secret_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "UserProperty" ADD CONSTRAINT "UserProperty_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "UserProperty" ADD CONSTRAINT "UserProperty_computedPropertyId_fkey" FOREIGN KEY ("computedPropertyId") REFERENCES "ComputedProperty"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "Segment" ADD CONSTRAINT "Segment_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "Segment" ADD CONSTRAINT "Segment_subscriptionGroupId_fkey" FOREIGN KEY ("subscriptionGroupId") REFERENCES "SubscriptionGroup"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "MessageTemplate" ADD CONSTRAINT "MessageTemplate_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "WriteKey" ADD CONSTRAINT "WriteKey_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "WriteKey" ADD CONSTRAINT "WriteKey_secretId_fkey" FOREIGN KEY ("secretId") REFERENCES "Secret"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "EmailProvider" ADD CONSTRAINT "EmailProvider_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "EmailProvider" ADD CONSTRAINT "EmailProvider_secretId_fkey" FOREIGN KEY ("secretId") REFERENCES "Secret"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "DefaultEmailProvider" ADD CONSTRAINT "DefaultEmailProvider_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "DefaultEmailProvider" ADD CONSTRAINT "DefaultEmailProvider_emailProviderId_fkey" FOREIGN KEY ("emailProviderId") REFERENCES "EmailProvider"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SmsProvider" ADD CONSTRAINT "SmsProvider_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SmsProvider" ADD CONSTRAINT "SmsProvider_secretId_fkey" FOREIGN KEY ("secretId") REFERENCES "Secret"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "DefaultSmsProvider" ADD CONSTRAINT "DefaultSmsProvider_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "DefaultSmsProvider" ADD CONSTRAINT "DefaultSmsProvider_smsProviderId_fkey" FOREIGN KEY ("smsProviderId") REFERENCES "SmsProvider"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "Journey" ADD CONSTRAINT "Journey_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SubscriptionGroup" ADD CONSTRAINT "SubscriptionGroup_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ComputedProperty" ADD CONSTRAINT "ComputedProperty_workspaceId_fkey" FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") ON DELETE CASCADE ON UPDATE CASCADE;