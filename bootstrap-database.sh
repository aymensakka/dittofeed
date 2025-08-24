#!/bin/bash

# Bootstrap Database Script for Dittofeed Multi-tenant
# This script sets up the database with all required tables and migrations

set -e

# Configuration
DB_HOST=${DATABASE_HOST:-localhost}
DB_PORT=${DATABASE_PORT:-5433}
DB_USER=${DATABASE_USER:-dittofeed}
DB_PASSWORD=${DATABASE_PASSWORD:-password}
DB_NAME=${DATABASE_NAME:-dittofeed}

echo "🚀 Starting Database Bootstrap..."

# Wait for database to be ready
echo "⏳ Waiting for PostgreSQL to be ready..."
until PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d postgres -c '\q' 2>/dev/null; do
  echo "PostgreSQL is unavailable - sleeping"
  sleep 2
done

echo "✅ PostgreSQL is ready!"

# Create database if it doesn't exist
echo "📦 Creating database if not exists..."
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d postgres -c "CREATE DATABASE $DB_NAME" 2>/dev/null || echo "Database already exists"

# Run Drizzle migrations
echo "🔄 Running Drizzle migrations..."
cd packages/backend-lib

# Apply all migrations
DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME" npx drizzle-kit push

# Apply embedded sessions migration if not already applied
echo "🔐 Applying embedded sessions migration..."
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << 'EOF'
-- Check if tables exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'EmbeddedSession') THEN
        -- Create Embedded Session tables
        CREATE TABLE "EmbeddedSession" (
            "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
            "sessionId" varchar(255) NOT NULL UNIQUE,
            "workspaceId" uuid NOT NULL,
            "refreshToken" varchar(500) NOT NULL UNIQUE,
            "refreshTokenFamily" uuid NOT NULL,
            "accessTokenHash" varchar(255) NOT NULL,
            "previousAccessTokenHash" varchar(255),
            "createdAt" timestamp DEFAULT now() NOT NULL,
            "lastRefreshedAt" timestamp DEFAULT now() NOT NULL,
            "expiresAt" timestamp NOT NULL,
            "refreshExpiresAt" timestamp NOT NULL,
            "revokedAt" timestamp,
            "revocationReason" varchar(100),
            "metadata" jsonb,
            "refreshCount" integer DEFAULT 0 NOT NULL,
            "ipAddress" varchar(45),
            "userAgent" text,
            "fingerprint" varchar(255)
        );

        CREATE INDEX "EmbeddedSession_workspaceId_idx" ON "EmbeddedSession" ("workspaceId");
        CREATE INDEX "EmbeddedSession_refreshToken_idx" ON "EmbeddedSession" ("refreshToken");
        CREATE INDEX "EmbeddedSession_sessionId_idx" ON "EmbeddedSession" ("sessionId");
        CREATE INDEX "EmbeddedSession_expiresAt_idx" ON "EmbeddedSession" ("expiresAt");
        CREATE INDEX "EmbeddedSession_refreshTokenFamily_idx" ON "EmbeddedSession" ("refreshTokenFamily");

        CREATE TABLE "EmbeddedSessionAudit" (
            "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
            "sessionId" varchar(255) NOT NULL,
            "workspaceId" uuid NOT NULL,
            "action" varchar(50) NOT NULL,
            "timestamp" timestamp DEFAULT now() NOT NULL,
            "ipAddress" varchar(45),
            "userAgent" text,
            "metadata" jsonb,
            "success" boolean DEFAULT true NOT NULL,
            "failureReason" varchar(255)
        );

        CREATE INDEX "EmbeddedSessionAudit_sessionId_idx" ON "EmbeddedSessionAudit" ("sessionId");
        CREATE INDEX "EmbeddedSessionAudit_workspaceId_idx" ON "EmbeddedSessionAudit" ("workspaceId");
        CREATE INDEX "EmbeddedSessionAudit_timestamp_idx" ON "EmbeddedSessionAudit" ("timestamp");
        CREATE INDEX "EmbeddedSessionAudit_action_idx" ON "EmbeddedSessionAudit" ("action");

        CREATE TABLE "EmbeddedSessionRateLimit" (
            "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
            "key" varchar(255) NOT NULL,
            "type" varchar(50) NOT NULL,
            "count" integer DEFAULT 1 NOT NULL,
            "windowStart" timestamp DEFAULT now() NOT NULL,
            UNIQUE("key", "type", "windowStart")
        );

        CREATE INDEX "EmbeddedSessionRateLimit_windowStart_idx" ON "EmbeddedSessionRateLimit" ("windowStart");

        -- Add foreign key constraints
        ALTER TABLE "EmbeddedSession" 
            ADD CONSTRAINT "EmbeddedSession_workspaceId_fkey" 
            FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") 
            ON UPDATE CASCADE ON DELETE CASCADE;

        ALTER TABLE "EmbeddedSessionAudit" 
            ADD CONSTRAINT "EmbeddedSessionAudit_workspaceId_fkey" 
            FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id") 
            ON UPDATE CASCADE ON DELETE CASCADE;

        -- Enable RLS
        ALTER TABLE "EmbeddedSession" ENABLE ROW LEVEL SECURITY;
        ALTER TABLE "EmbeddedSessionAudit" ENABLE ROW LEVEL SECURITY;

        -- Create RLS policies
        CREATE POLICY "EmbeddedSession_workspace_isolation" ON "EmbeddedSession"
            USING ("workspaceId" = current_setting('app.current_workspace')::uuid);

        CREATE POLICY "EmbeddedSessionAudit_workspace_isolation" ON "EmbeddedSessionAudit"
            USING ("workspaceId" = current_setting('app.current_workspace')::uuid);

        RAISE NOTICE 'Embedded session tables created successfully';
    ELSE
        RAISE NOTICE 'Embedded session tables already exist';
    END IF;
END $$;
EOF

# Create default Root workspace if not exists
echo "🏢 Creating default workspace..."
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME << 'EOF'
INSERT INTO "Workspace" (id, name, type, "createdAt", "updatedAt", status)
VALUES (
    'a3184198-612f-4a12-82b1-7f706c93912d',
    'Default Workspace',
    'Root',
    NOW(),
    NOW(),
    'Active'
) ON CONFLICT (id) DO NOTHING;
EOF

echo "✨ Database bootstrap complete!"
echo ""
echo "Next steps:"
echo "1. Start the API server: ./start-api-local.sh"
echo "2. Start the Dashboard: ./start-dashboard-local.sh"
echo "3. Create child workspaces using the Admin API"
echo "4. Test embedded dashboard using test-embedded-iframe.html"