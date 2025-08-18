#!/bin/bash

# ==============================================================================
# Check Migration and Bootstrap Status
# ==============================================================================

echo "===================================================="
echo "Checking Migration and Bootstrap Status"
echo "===================================================="

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Find containers
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)

echo "Checking database status..."
echo ""

# Check if migrations have created tables
echo "1. Checking database tables (migrations create these):"
TABLE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
TABLE_COUNT=$(echo $TABLE_COUNT | tr -d ' ')
echo "   Found $TABLE_COUNT tables in database"

if [ "$TABLE_COUNT" -gt "0" ]; then
    echo ""
    echo "   Tables created by migrations:"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\dt" 2>/dev/null | head -20
fi

echo ""
echo "2. Checking for workspaces (created by bootstrap):"
WORKSPACE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM \"Workspace\";" 2>/dev/null || echo "0")
WORKSPACE_COUNT=$(echo $WORKSPACE_COUNT | tr -d ' ')

if [ "$WORKSPACE_COUNT" != "0" ]; then
    echo "   Found $WORKSPACE_COUNT workspace(s):"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain, created_at FROM \"Workspace\";" 2>/dev/null
else
    echo "   No workspaces found yet"
fi

echo ""
echo "3. Checking API container logs for migration/bootstrap activity:"
docker logs $API_CONTAINER --tail 30 2>&1 | grep -i "migrat\|bootstrap\|workspace\|table\|schema" || echo "   No relevant logs found"

echo ""
echo "4. Checking if API is responding:"
docker exec $API_CONTAINER sh -c "curl -s http://localhost:3001/api/public/health || echo 'API not responding'" 2>/dev/null || echo "Could not check API"

echo ""
echo "===================================================="
echo "Status Check Complete"
echo "===================================================="

if [ "$TABLE_COUNT" -gt "30" ]; then
    echo "✓ Migrations appear to be complete (found $TABLE_COUNT tables)"
else
    echo "⚠ Migrations may still be running or failed (only $TABLE_COUNT tables)"
fi

if [ "$WORKSPACE_COUNT" != "0" ]; then
    echo "✓ Bootstrap appears to be complete (found $WORKSPACE_COUNT workspace(s))"
else
    echo "⚠ Bootstrap has not created a workspace yet"
fi