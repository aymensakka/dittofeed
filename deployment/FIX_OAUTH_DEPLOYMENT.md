# Fix Dittofeed Multi-Tenant OAuth and Database Issues

## Current Situation
I have a Dittofeed multi-tenant deployment running in Docker containers managed by Coolify. The application has the following issues:
1. Dashboard shows "anonymous@email.com" instead of Google OAuth login
2. Database may be missing OAuth provider configuration
3. Multi-tenant authentication is not working properly

## Project Context
- **Project ID**: `p0gcsc088cogco0cokco4404`
- **Dashboard URL**: https://communication-dashboard.caramelme.com
- **API URL**: https://communication-api.caramelme.com
- **Deployment**: Docker containers managed by Coolify
- **Auth Mode Required**: `multi-tenant` (NOT single-tenant)

## What I Need You To Fix

### 1. Find All Running Containers
First, identify all Dittofeed containers:
```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep p0gcsc088cogco0cokco4404
```

Store the container names in variables for easy access:
```bash
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*p0gcsc088cogco0cokco4404" | head -1)
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*p0gcsc088cogco0cokco4404" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*p0gcsc088cogco0cokco4404" | head -1)
WORKER_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "worker.*p0gcsc088cogco0cokco4404" | head -1)
```

### 2. Fix Database Schema
The database needs proper multi-tenant schema. Run these fixes:

```bash
# Add missing columns to Workspace table
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
ALTER TABLE "Workspace" ADD COLUMN IF NOT EXISTS domain TEXT;
ALTER TABLE "Workspace" ADD COLUMN IF NOT EXISTS "externalId" TEXT;
ALTER TABLE "Workspace" ADD COLUMN IF NOT EXISTS "parentWorkspaceId" UUID REFERENCES "Workspace"(id);
ALTER TABLE "WorkspaceMemberRole" ADD COLUMN IF NOT EXISTS "resourceType" TEXT;
EOF

# Check if workspace exists
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, status, domain FROM \"Workspace\";"
```

### 3. Create/Fix Workspace
If no workspace exists or domain is NULL:

```bash
# Get or create workspace
WORKSPACE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM \"Workspace\";" | tr -d ' ')

if [ "$WORKSPACE_COUNT" = "0" ]; then
    # Create new workspace
    WORKSPACE_ID=$(uuidgen || echo "ws-$(date +%s)")
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
INSERT INTO "Workspace" (id, name, type, status, domain, "createdAt", "updatedAt")
VALUES ('$WORKSPACE_ID', 'caramel', 'Root', 'Active', 'caramelme.com', NOW(), NOW());
EOF
else
    # Update existing workspace domain
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
        "UPDATE \"Workspace\" SET domain = 'caramelme.com' WHERE domain IS NULL;"
    WORKSPACE_ID=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT id FROM \"Workspace\" LIMIT 1;" | tr -d ' ')
fi

echo "Workspace ID: $WORKSPACE_ID"
```

### 4. Fix OAuth Provider Configuration
This is critical for Google OAuth to work:

```bash
# First, fix the AuthProvider table column name if needed
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'AuthProvider' AND column_name = 'provider') THEN
        ALTER TABLE "AuthProvider" RENAME COLUMN provider TO type;
    END IF;
END\$\$;
EOF

# Clean up and recreate OAuth provider
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
DELETE FROM "AuthProvider" WHERE "workspaceId" = '$WORKSPACE_ID';

INSERT INTO "AuthProvider" (
    "workspaceId", "type", "enabled", "config", "createdAt", "updatedAt"
) VALUES (
    '$WORKSPACE_ID', 
    'google', 
    true,
    '{"provider": "google", "scope": ["openid", "email", "profile"]}',
    NOW(), 
    NOW()
);
EOF

# Verify OAuth provider exists
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT * FROM \"AuthProvider\" WHERE type = 'google';"
```

### 5. Check Dashboard Environment Variables
The dashboard container MUST have these environment variables:

```bash
# Check current environment variables
docker exec $DASHBOARD_CONTAINER env | grep -E "AUTH_MODE|NEXT_PUBLIC|GOOGLE"
```

The dashboard should have:
- `AUTH_MODE=multi-tenant`
- `NEXT_PUBLIC_AUTH_MODE=multi-tenant`

### 6. Check API Environment Variables
The API container must also be configured correctly:

```bash
# Check API environment
docker exec $API_CONTAINER env | grep -E "AUTH_MODE|GOOGLE|DATABASE_URL"
```

### 7. Verify API Routes
Check if the multi-tenant auth routes are accessible:

```bash
# Get API container IP
API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER | head -c -1)

# Test auth route (should return something, not 404)
curl -I "http://${API_IP}:3001/api/public/auth/providers"
```

### 8. Restart Services
After making all database changes:

```bash
docker restart $API_CONTAINER
docker restart $DASHBOARD_CONTAINER
docker restart $WORKER_CONTAINER
```

### 9. Check Logs for Errors
```bash
echo "=== API Logs ==="
docker logs $API_CONTAINER --tail 20

echo "=== Dashboard Logs ==="
docker logs $DASHBOARD_CONTAINER --tail 20
```

### 10. Get Container IPs for Cloudflare Tunnel
```bash
API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER | head -c -1)
DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER | head -c -1)

echo "Cloudflare Tunnel Configuration:"
echo "  communication-api.caramelme.com → http://${API_IP}:3001"
echo "  communication-dashboard.caramelme.com → http://${DASHBOARD_IP}:3000"
```

## Expected Results
After running these fixes:
1. Workspace should exist with domain = 'caramelme.com'
2. AuthProvider table should have Google OAuth configured
3. Dashboard should show Google login instead of anonymous mode
4. API should respond to `/api/public/auth` routes

## If Dashboard Still Shows Anonymous Mode
The dashboard image may need to be rebuilt with AUTH_MODE=multi-tenant baked in at BUILD time. Check if the dashboard image has the correct auth mode:

```bash
docker inspect $DASHBOARD_CONTAINER | grep -A 5 "Env"
```

If AUTH_MODE is not multi-tenant or missing, the dashboard Docker image needs to be rebuilt with these environment variables set during the build process (not just runtime).

## Important Notes
- NEVER switch to single-tenant mode
- AUTH_MODE must be set at BUILD time for the dashboard, not just runtime
- The OAuth routes are at `/api/public/auth` for multi-tenant mode
- All database tables must include workspaceId for multi-tenancy

Please run through all these steps and report any errors or issues you encounter.