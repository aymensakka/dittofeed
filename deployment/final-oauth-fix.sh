#!/bin/bash

# ==============================================================================
# Final OAuth Fix - Insert Provider and Fix API Routes
# ==============================================================================

set -e

echo "===================================================="
echo "Final OAuth Fix"
echo "===================================================="
echo ""

PROJECT_ID="p0gcsc088cogco0cokco4404"
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)

echo "Containers:"
echo "  Postgres: $POSTGRES_CONTAINER"
echo "  API: $API_CONTAINER"
echo "  Dashboard: $DASHBOARD_CONTAINER"
echo ""

# Step 1: Insert OAuth provider (the table is empty!)
echo "Step 1: Inserting Google OAuth provider..."
WORKSPACE_ID=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c \
    "SELECT id FROM \"Workspace\" WHERE name = 'caramel' OR type = 'Root' LIMIT 1;" 2>/dev/null | tr -d ' \n')

if [ -z "$WORKSPACE_ID" ]; then
    echo "❌ No workspace found! Creating one..."
    WORKSPACE_ID=$(uuidgen 2>/dev/null || echo "$(date +%s)-$(shuf -i 1000-9999 -n 1)")
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
INSERT INTO "Workspace" (
    id, name, type, status, domain, "createdAt", "updatedAt"
) VALUES (
    '$WORKSPACE_ID', 'caramel', 'Root', 'Active', 'caramelme.com', NOW(), NOW()
) ON CONFLICT (name) DO UPDATE SET domain = 'caramelme.com'
RETURNING id;
EOF
fi

echo "Workspace ID: $WORKSPACE_ID"

# Insert OAuth provider
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
INSERT INTO "AuthProvider" (
    "workspaceId",
    "type",
    "enabled",
    "config",
    "createdAt",
    "updatedAt"
) VALUES (
    '$WORKSPACE_ID',
    'google',
    true,
    '{"provider": "google", "scope": ["openid", "email", "profile"]}',
    NOW(),
    NOW()
) ON CONFLICT ("workspaceId", "type") 
DO UPDATE SET 
    "enabled" = true,
    "config" = '{"provider": "google", "scope": ["openid", "email", "profile"]}',
    "updatedAt" = NOW();
EOF

echo "✅ OAuth provider inserted"
echo ""

# Step 2: Verify OAuth provider exists
echo "Step 2: Verifying OAuth provider..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "SELECT type, enabled, config FROM \"AuthProvider\";" 2>&1
echo ""

# Step 3: Check API configuration
echo "Step 3: Checking API configuration..."
echo "API environment variables:"
docker exec $API_CONTAINER env | grep -E "AUTH_MODE|DATABASE_URL|NODE_ENV" | head -10
echo ""

# Step 4: Check API routes
echo "Step 4: Testing API routes directly..."
echo -n "Testing /health endpoint: "
docker exec $API_CONTAINER curl -s -f http://localhost:3001/health 2>&1 | head -c 100 || echo "Not found"
echo ""
echo -n "Testing /api/health endpoint: "
docker exec $API_CONTAINER curl -s -f http://localhost:3001/api/health 2>&1 | head -c 100 || echo "Not found"
echo ""

# Step 5: Check API startup logs for errors
echo "Step 5: Checking API startup logs..."
docker logs $API_CONTAINER 2>&1 | grep -i "error\|fail\|critical" | head -10 || echo "No obvious errors"
echo ""

# Step 6: Fix container IPs in Cloudflare
echo "Step 6: Updating container IPs..."
NEW_API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER 2>/dev/null | head -1)
NEW_DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER 2>/dev/null | head -1)

echo "Current IPs:"
echo "  API: $NEW_API_IP"
echo "  Dashboard: $NEW_DASHBOARD_IP"
echo ""

# Update Cloudflare tunnel
CLOUDFLARED=$(docker ps --format '{{.Names}}' | grep cloudflared | head -1)
if [ ! -z "$CLOUDFLARED" ]; then
    echo "Updating Cloudflare tunnel configuration..."
    cat > /tmp/cloudflared-config.yml << EOF
tunnel: auto
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: communication-api.caramelme.com
    service: http://${NEW_API_IP}:3001
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      
  - hostname: communication-dashboard.caramelme.com
    service: http://${NEW_DASHBOARD_IP}:3000
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      
  - service: http_status:404
EOF
    
    docker cp /tmp/cloudflared-config.yml ${CLOUDFLARED}:/etc/cloudflared/config.yml 2>/dev/null && {
        docker restart ${CLOUDFLARED} > /dev/null 2>&1
        echo "✅ Cloudflare tunnel updated with new IPs"
    } || {
        echo "⚠️  Could not update Cloudflare config"
        echo "Update manually in Cloudflare Zero Trust dashboard:"
        echo "  API: http://${NEW_API_IP}:3001"
        echo "  Dashboard: http://${NEW_DASHBOARD_IP}:3000"
    }
fi

# Step 7: Restart services one more time
echo ""
echo "Step 7: Final service restart..."
docker restart $API_CONTAINER > /dev/null 2>&1
sleep 5
docker restart $DASHBOARD_CONTAINER > /dev/null 2>&1
echo "✅ Services restarted"

echo ""
echo "⏳ Waiting 30 seconds for services to stabilize..."
sleep 30

# Step 8: Final test
echo ""
echo "Step 8: Final test..."
echo -n "API health: "
curl -s -o /dev/null -w "%{http_code}" https://communication-api.caramelme.com/health 2>/dev/null || echo "Failed"

echo -n "Dashboard: "
curl -s -o /dev/null -w "%{http_code}" https://communication-dashboard.caramelme.com/dashboard 2>/dev/null || echo "Failed"

echo ""
echo ""
echo "===================================================="
echo "Final Status"
echo "===================================================="
echo ""
echo "OAuth provider is now configured in the database."
echo ""
echo "Visit: https://communication-dashboard.caramelme.com/dashboard"
echo ""
echo "IMPORTANT: If you still see 'anonymous@email.com':"
echo "  The dashboard Docker image was built without AUTH_MODE=multi-tenant"
echo "  You MUST rebuild the dashboard image:"
echo ""
echo "  cd ~/dittofeed"
echo "  ./deployment/build-dashboard-docker-only.sh"
echo ""
echo "This will build and push a new dashboard image with OAuth enabled."
echo "Then redeploy from Coolify with the new image."
echo "===================================================="