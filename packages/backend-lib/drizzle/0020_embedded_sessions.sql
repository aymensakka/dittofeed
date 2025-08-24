-- Create table for tracking embedded sessions with security features
CREATE TABLE IF NOT EXISTS "EmbeddedSession" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
    "sessionId" varchar(255) NOT NULL UNIQUE,
    "workspaceId" uuid NOT NULL,
    "refreshToken" varchar(500) NOT NULL UNIQUE,
    "refreshTokenFamily" uuid NOT NULL, -- For detecting token reuse attacks
    "accessTokenHash" varchar(255) NOT NULL, -- Store hash of current access token
    "previousAccessTokenHash" varchar(255), -- For grace period during rotation
    "createdAt" timestamp DEFAULT now() NOT NULL,
    "lastRefreshedAt" timestamp DEFAULT now() NOT NULL,
    "expiresAt" timestamp NOT NULL,
    "refreshExpiresAt" timestamp NOT NULL, -- Absolute expiry for refresh token
    "revokedAt" timestamp, -- For explicit revocation
    "revocationReason" varchar(100), -- 'manual', 'token_reuse', 'expired', 'security'
    "metadata" jsonb, -- Store additional context (IP, user agent, etc.)
    "refreshCount" integer DEFAULT 0 NOT NULL,
    "ipAddress" varchar(45),
    "userAgent" text,
    "fingerprint" varchar(255) -- Browser fingerprint for additional security
);

-- Create indexes for performance
CREATE INDEX "EmbeddedSession_workspaceId_idx" ON "EmbeddedSession" ("workspaceId");
CREATE INDEX "EmbeddedSession_refreshToken_idx" ON "EmbeddedSession" ("refreshToken");
CREATE INDEX "EmbeddedSession_sessionId_idx" ON "EmbeddedSession" ("sessionId");
CREATE INDEX "EmbeddedSession_expiresAt_idx" ON "EmbeddedSession" ("expiresAt");
CREATE INDEX "EmbeddedSession_refreshTokenFamily_idx" ON "EmbeddedSession" ("refreshTokenFamily");

-- Create table for session audit log
CREATE TABLE IF NOT EXISTS "EmbeddedSessionAudit" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
    "sessionId" varchar(255) NOT NULL,
    "workspaceId" uuid NOT NULL,
    "action" varchar(50) NOT NULL, -- 'created', 'refreshed', 'revoked', 'expired', 'reuse_detected'
    "timestamp" timestamp DEFAULT now() NOT NULL,
    "ipAddress" varchar(45),
    "userAgent" text,
    "metadata" jsonb,
    "success" boolean DEFAULT true NOT NULL,
    "failureReason" varchar(255)
);

-- Create index for audit queries
CREATE INDEX "EmbeddedSessionAudit_sessionId_idx" ON "EmbeddedSessionAudit" ("sessionId");
CREATE INDEX "EmbeddedSessionAudit_workspaceId_idx" ON "EmbeddedSessionAudit" ("workspaceId");
CREATE INDEX "EmbeddedSessionAudit_timestamp_idx" ON "EmbeddedSessionAudit" ("timestamp");
CREATE INDEX "EmbeddedSessionAudit_action_idx" ON "EmbeddedSessionAudit" ("action");

-- Create table for rate limiting
CREATE TABLE IF NOT EXISTS "EmbeddedSessionRateLimit" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
    "key" varchar(255) NOT NULL, -- IP address or workspace ID
    "type" varchar(50) NOT NULL, -- 'refresh', 'create'
    "count" integer DEFAULT 1 NOT NULL,
    "windowStart" timestamp DEFAULT now() NOT NULL,
    UNIQUE("key", "type", "windowStart")
);

-- Create index for rate limit cleanup
CREATE INDEX "EmbeddedSessionRateLimit_windowStart_idx" ON "EmbeddedSessionRateLimit" ("windowStart");

-- Add RLS policies for workspace isolation
ALTER TABLE "EmbeddedSession" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "EmbeddedSessionAudit" ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "EmbeddedSession_workspace_isolation" ON "EmbeddedSession"
    USING ("workspaceId" = current_setting('app.current_workspace')::uuid);

CREATE POLICY "EmbeddedSessionAudit_workspace_isolation" ON "EmbeddedSessionAudit"
    USING ("workspaceId" = current_setting('app.current_workspace')::uuid);