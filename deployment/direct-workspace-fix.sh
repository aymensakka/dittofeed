#!/bin/bash

# ==============================================================================
# Direct Workspace Creation and API Fix
# ==============================================================================

echo "===================================================="
echo "Direct Workspace Creation and API Fix"
echo "===================================================="

PROJECT_ID="p0gcsc088cogco0cokco4404"
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)

echo "Containers:"
echo "  Postgres: $POSTGRES_CONTAINER"
echo "  API: $API_CONTAINER"
echo "  Dashboard: $DASHBOARD_CONTAINER"
echo ""

echo "Step 1: Checking current workspace content..."
echo "Count in Workspace table:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT COUNT(*) FROM \"Workspace\";" 2>/dev/null

echo ""
echo "Content of Workspace table:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT * FROM \"Workspace\";" 2>/dev/null

echo ""
echo "Step 2: Checking Workspace table structure..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\d \"Workspace\"" 2>/dev/null | head -30

echo ""
echo "Step 3: Creating workspace directly in database..."
WORKSPACE_ID=$(uuidgen 2>/dev/null || echo "ws-$(date +%s)")

# Insert workspace with all required fields
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
INSERT INTO "Workspace" (
    id,
    name,
    type,
    domain,
    "createdAt",
    "updatedAt"
) VALUES (
    '$WORKSPACE_ID',
    'caramel',
    'Root',
    'caramelme.com',
    NOW(),
    NOW()
) ON CONFLICT (id) DO NOTHING;
EOF

echo ""
echo "Step 4: Verifying workspace was created..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM \"Workspace\";" 2>/dev/null

echo ""
echo "Step 5: Creating default user properties for the workspace..."
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed << EOF
-- Insert default user properties if they don't exist
INSERT INTO "UserProperty" (id, "workspaceId", name, definition, "createdAt", "updatedAt")
SELECT 
    gen_random_uuid()::text,
    '$WORKSPACE_ID',
    prop.name,
    prop.definition::jsonb,
    NOW(),
    NOW()
FROM (
    VALUES 
        ('email', '{"type": "Trait"}'),
        ('firstName', '{"type": "Trait"}'),
        ('lastName', '{"type": "Trait"}'),
        ('phone', '{"type": "Trait"}'),
        ('id', '{"type": "Id"}'),
        ('anonymousId', '{"type": "AnonymousId"}')
) AS prop(name, definition)
WHERE NOT EXISTS (
    SELECT 1 FROM "UserProperty" 
    WHERE "workspaceId" = '$WORKSPACE_ID' AND name = prop.name
);
EOF

echo ""
echo "Step 6: Checking API startup issues..."
echo "API Environment Variables:"
docker exec $API_CONTAINER env | grep -E "DATABASE|AUTH_MODE|WORKSPACE|BOOTSTRAP" | sort

echo ""
echo "API process status:"
docker exec $API_CONTAINER sh -c "ps aux | grep node" 2>/dev/null | head -3

echo ""
echo "Step 7: Testing API endpoints..."
API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER | head -c -1 | tr -d '\n')
echo "API IP: $API_IP"

# Test from API container itself
echo "Testing localhost from API container:"
docker exec $API_CONTAINER sh -c "wget -qO- http://localhost:3001/api/public/health 2>&1 || echo 'Failed'" | head -5

# Test the root endpoint
echo ""
echo "Testing root endpoint:"
docker exec $API_CONTAINER sh -c "wget -qO- http://localhost:3001/ 2>&1 || echo 'Failed'" | head -5

echo ""
echo "Step 8: Checking API logs for startup errors..."
docker logs $API_CONTAINER --tail 20 2>&1

echo ""
echo "Step 9: Restarting services with workspace created..."
docker restart $API_CONTAINER
sleep 10
docker restart $DASHBOARD_CONTAINER
sleep 5

echo ""
echo "Step 10: Final verification..."
echo "Workspace in database:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM \"Workspace\" WHERE name = 'caramel';" 2>/dev/null

echo ""
echo "API Status:"
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep "$API_CONTAINER"

echo ""
echo "Dashboard Status:"
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep "$DASHBOARD_CONTAINER"

echo ""
echo "===================================================="
echo "Complete!"
echo "===================================================="
echo ""
echo "Workspace 'caramel' has been created directly in the database."
echo "Services have been restarted."
echo ""
echo "Try accessing: https://communication-dashboard.caramelme.com"
echo ""
echo "If you see a login page, the deployment is working!"
echo "If you still see 404, check the dashboard logs:"
echo "  docker logs $DASHBOARD_CONTAINER --tail 50"