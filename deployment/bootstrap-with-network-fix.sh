#!/bin/bash

# ==============================================================================
# Complete Bootstrap with Network Fix - Full setup with IP management
# Use this for: Complete setup, network issues, IP changes after restart
# This script:
# 1. Finds all containers dynamically
# 2. Updates environment variables for proper internal networking
# 3. Runs bootstrap if needed
# 4. Handles IP changes after restart
# 5. Provides Cloudflare tunnel configuration
# ==============================================================================

set -e

echo "===================================================="
echo "Complete Bootstrap with Network Configuration"
echo "===================================================="

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Function to find all containers
find_all_containers() {
    API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
    POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
    DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
    WORKER_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "worker.*${PROJECT_ID}" | head -1)
    TEMPORAL_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "temporal.*${PROJECT_ID}" | head -1)
    CLICKHOUSE_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "clickhouse.*${PROJECT_ID}" | head -1)
    REDIS_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "redis.*${PROJECT_ID}" | head -1)
    CLOUDFLARED_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "cloudflared.*${PROJECT_ID}" | head -1)
}

# Function to get all container IPs
get_all_ips() {
    [ ! -z "$API_CONTAINER" ] && API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')
    [ ! -z "$POSTGRES_CONTAINER" ] && POSTGRES_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $POSTGRES_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')
    [ ! -z "$DASHBOARD_CONTAINER" ] && DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')
    [ ! -z "$TEMPORAL_CONTAINER" ] && TEMPORAL_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $TEMPORAL_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')
    [ ! -z "$CLICKHOUSE_CONTAINER" ] && CLICKHOUSE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CLICKHOUSE_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')
    [ ! -z "$REDIS_CONTAINER" ] && REDIS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $REDIS_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')
    [ ! -z "$WORKER_CONTAINER" ] && WORKER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $WORKER_CONTAINER 2>/dev/null | head -c -1 | tr -d '\n')
}

# Step 1: Find all containers
echo "Step 1: Finding containers..."
find_all_containers

echo ""
echo "Found containers:"
echo "  API: ${API_CONTAINER:-NOT FOUND}"
echo "  Postgres: ${POSTGRES_CONTAINER:-NOT FOUND}"
echo "  Dashboard: ${DASHBOARD_CONTAINER:-NOT FOUND}"
echo "  Worker: ${WORKER_CONTAINER:-NOT FOUND}"
echo "  Temporal: ${TEMPORAL_CONTAINER:-NOT FOUND}"
echo "  ClickHouse: ${CLICKHOUSE_CONTAINER:-NOT FOUND}"
echo "  Redis: ${REDIS_CONTAINER:-NOT FOUND}"
echo "  Cloudflared: ${CLOUDFLARED_CONTAINER:-NOT FOUND}"

# Check critical containers
if [ -z "$API_CONTAINER" ] || [ -z "$POSTGRES_CONTAINER" ] || [ -z "$DASHBOARD_CONTAINER" ]; then
    echo ""
    echo "⚠️  Critical containers missing. Checking for stopped containers..."
    
    # Check for stopped containers
    STOPPED=$(docker ps -a --filter "status=exited" --format '{{.Names}}' | grep "${PROJECT_ID}" || true)
    if [ ! -z "$STOPPED" ]; then
        echo "Found stopped containers:"
        echo "$STOPPED"
        echo ""
        
        # Show logs of stopped containers for debugging
        echo "Checking logs of stopped containers:"
        for container in $STOPPED; do
            echo ""
            echo "Last 10 lines from $container:"
            docker logs $container --tail 10 2>&1 | head -15 || echo "Could not get logs"
            echo "---"
        done
        
        echo ""
        echo "Attempting to start stopped containers..."
        for container in $STOPPED; do
            echo "Starting $container..."
            docker start $container 2>/dev/null || echo "Could not start $container"
        done
        sleep 10
        
        # Re-find containers
        find_all_containers
    fi
    
    if [ -z "$API_CONTAINER" ] || [ -z "$POSTGRES_CONTAINER" ]; then
        echo "❌ Critical containers still missing. Please check Coolify deployment."
        exit 1
    fi
fi

# Step 2: Get container IPs
echo ""
echo "Step 2: Getting container IPs..."
get_all_ips

echo ""
echo "Container IPs:"
[ ! -z "$API_IP" ] && echo "  API: ${API_IP}:3001"
[ ! -z "$DASHBOARD_IP" ] && echo "  Dashboard: ${DASHBOARD_IP}:3000"
[ ! -z "$POSTGRES_IP" ] && echo "  Postgres: ${POSTGRES_IP}:5432"
[ ! -z "$TEMPORAL_IP" ] && echo "  Temporal: ${TEMPORAL_IP}:7233"
[ ! -z "$CLICKHOUSE_IP" ] && echo "  ClickHouse: ${CLICKHOUSE_IP}:8123"
[ ! -z "$REDIS_IP" ] && echo "  Redis: ${REDIS_IP}:6379"
[ ! -z "$WORKER_IP" ] && echo "  Worker: ${WORKER_IP}"

# Step 3: Update environment variables in containers
echo ""
echo "Step 3: Updating container environment variables..."

# Update Dashboard environment
if [ ! -z "$DASHBOARD_CONTAINER" ] && [ ! -z "$API_IP" ]; then
    echo "Updating dashboard to use API at ${API_IP}:3001..."
    
    docker exec $DASHBOARD_CONTAINER sh -c "
    export API_BASE_URL='http://${API_IP}:3001'
    export NEXT_PUBLIC_API_BASE_URL='http://${API_IP}:3001'
    export INTERNAL_API_URL='http://${API_IP}:3001'
    export DATABASE_HOST='${POSTGRES_IP}'
    export DATABASE_URL='postgresql://dittofeed:\${DATABASE_PASSWORD}@${POSTGRES_IP}:5432/dittofeed'
    export CLICKHOUSE_HOST='http://${CLICKHOUSE_IP}:8123'
    export REDIS_HOST='${REDIS_IP}'
    export TEMPORAL_ADDRESS='${TEMPORAL_IP}:7233'
    echo 'Dashboard environment updated'
    " 2>/dev/null || echo "Could not update dashboard environment"
fi

# Update API environment
if [ ! -z "$API_CONTAINER" ]; then
    echo "Updating API environment variables..."
    
    docker exec $API_CONTAINER sh -c "
    export DATABASE_HOST='${POSTGRES_IP}'
    export DATABASE_URL='postgresql://dittofeed:\${DATABASE_PASSWORD}@${POSTGRES_IP}:5432/dittofeed'
    export DASHBOARD_URL='http://${DASHBOARD_IP}:3000'
    export CLICKHOUSE_HOST='http://${CLICKHOUSE_IP}:8123'
    export REDIS_HOST='${REDIS_IP}'
    export TEMPORAL_ADDRESS='${TEMPORAL_IP}:7233'
    echo 'API environment updated'
    " 2>/dev/null || echo "Could not update API environment"
fi

# Update Worker environment
if [ ! -z "$WORKER_CONTAINER" ]; then
    echo "Updating Worker environment variables..."
    
    docker exec $WORKER_CONTAINER sh -c "
    export DATABASE_HOST='${POSTGRES_IP}'
    export DATABASE_URL='postgresql://dittofeed:\${DATABASE_PASSWORD}@${POSTGRES_IP}:5432/dittofeed'
    export API_URL='http://${API_IP}:3001'
    export CLICKHOUSE_HOST='http://${CLICKHOUSE_IP}:8123'
    export REDIS_HOST='${REDIS_IP}'
    export TEMPORAL_ADDRESS='${TEMPORAL_IP}:7233'
    echo 'Worker environment updated'
    " 2>/dev/null || echo "Could not update Worker environment"
fi

# Step 4: Check connectivity
echo ""
echo "Step 4: Testing connectivity..."
if [ ! -z "$API_CONTAINER" ]; then
    # Check if API process is running
    echo "API process check:"
    docker exec $API_CONTAINER sh -c "ps aux 2>/dev/null | grep -E 'node|npm' | grep -v grep | head -2" 2>/dev/null || echo "  Could not check processes"
    
    echo ""
    echo "Service connectivity:"
    # Test database connection
    docker exec $API_CONTAINER sh -c "nc -zv ${POSTGRES_IP} 5432 2>&1 | grep -q succeeded" && echo "  ✅ API → Database" || echo "  ❌ API → Database"
    
    # Test other services
    [ ! -z "$TEMPORAL_IP" ] && (docker exec $API_CONTAINER sh -c "nc -zv ${TEMPORAL_IP} 7233 2>&1 | grep -q succeeded" && echo "  ✅ API → Temporal" || echo "  ❌ API → Temporal")
    [ ! -z "$CLICKHOUSE_IP" ] && (docker exec $API_CONTAINER sh -c "nc -zv ${CLICKHOUSE_IP} 8123 2>&1 | grep -q succeeded" && echo "  ✅ API → ClickHouse" || echo "  ❌ API → ClickHouse")
    [ ! -z "$REDIS_IP" ] && (docker exec $API_CONTAINER sh -c "nc -zv ${REDIS_IP} 6379 2>&1 | grep -q succeeded" && echo "  ✅ API → Redis" || echo "  ❌ API → Redis")
fi

if [ ! -z "$DASHBOARD_CONTAINER" ] && [ ! -z "$API_IP" ]; then
    docker exec $DASHBOARD_CONTAINER sh -c "nc -zv ${API_IP} 3001 2>&1 | grep -q succeeded" && echo "  ✅ Dashboard → API" || echo "  ❌ Dashboard → API"
fi

# Step 5: Check and create workspace if needed
echo ""
echo "Step 5: Checking workspace..."
WORKSPACE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM \"Workspace\";" 2>/dev/null || echo "0")
WORKSPACE_COUNT=$(echo $WORKSPACE_COUNT | tr -d ' ')

if [ "$WORKSPACE_COUNT" = "0" ]; then
    echo "No workspace found. Creating default workspace..."
    
    # Try bootstrap via API first
    if [ ! -z "$API_CONTAINER" ]; then
        docker exec -e AUTH_MODE=multi-tenant $API_CONTAINER node -e "
        const path = require('path');
        const bootstrapPath = path.join('/service/packages/backend-lib/dist/src/bootstrap.js');
        
        try {
            const { bootstrapWithDefaults } = require(bootstrapPath);
            bootstrapWithDefaults({
                workspaceName: 'caramel',
                workspaceDomain: 'caramelme.com',
                workspaceType: 'Root'
            }).then(() => {
                console.log('✅ Workspace created');
                process.exit(0);
            }).catch(err => {
                console.error('Bootstrap error:', err.message);
                process.exit(1);
            });
        } catch (err) {
            console.error('Could not load bootstrap:', err.message);
            process.exit(1);
        }
        " 2>/dev/null || {
            echo "Bootstrap via API failed, creating directly in database..."
            
            WORKSPACE_ID=$(uuidgen 2>/dev/null || echo "ws-$(date +%s)")
            docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "
            INSERT INTO \"Workspace\" (id, name, type, status, \"createdAt\", \"updatedAt\")
            VALUES ('$WORKSPACE_ID', 'caramel', 'Root', 'Active', NOW(), NOW())
            ON CONFLICT (name) DO NOTHING;
            " 2>/dev/null
        }
    fi
else
    echo "Found $WORKSPACE_COUNT workspace(s):"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, status FROM \"Workspace\";" 2>/dev/null
fi

# Step 6: Save IPs before restart
echo ""
echo "Step 6: Restarting services..."
API_IP_BEFORE=$API_IP
DASHBOARD_IP_BEFORE=$DASHBOARD_IP

# Restart services
[ ! -z "$API_CONTAINER" ] && docker restart $API_CONTAINER > /dev/null 2>&1
sleep 5
[ ! -z "$WORKER_CONTAINER" ] && docker restart $WORKER_CONTAINER > /dev/null 2>&1
sleep 3
[ ! -z "$DASHBOARD_CONTAINER" ] && docker restart $DASHBOARD_CONTAINER > /dev/null 2>&1
sleep 5

# Step 7: Check for IP changes after restart
echo ""
echo "Step 7: Checking for IP changes after restart..."

# Re-find containers (in case names changed)
find_all_containers

# Get new IPs
get_all_ips

# Compare IPs
IP_CHANGED=false
if [ "$API_IP_BEFORE" != "$API_IP" ] || [ "$DASHBOARD_IP_BEFORE" != "$DASHBOARD_IP" ]; then
    IP_CHANGED=true
    echo ""
    echo "⚠️  IMPORTANT: Container IPs have changed!"
    echo "================================================="
    echo "IP CHANGES DETECTED - UPDATE CLOUDFLARE TUNNEL"
    echo "================================================="
    [ "$API_IP_BEFORE" != "$API_IP" ] && echo "  API: $API_IP_BEFORE → $API_IP"
    [ "$DASHBOARD_IP_BEFORE" != "$DASHBOARD_IP" ] && echo "  Dashboard: $DASHBOARD_IP_BEFORE → $DASHBOARD_IP"
    echo "================================================="
else
    echo "✅ IPs unchanged after restart"
fi

# Step 8: Final status and configuration
echo ""
echo "===================================================="
echo "Final Configuration"
echo "===================================================="

# Check services health
echo ""
echo "Service Status:"
for container in "$API_CONTAINER" "$DASHBOARD_CONTAINER" "$WORKER_CONTAINER" "$TEMPORAL_CONTAINER" "$POSTGRES_CONTAINER" "$CLICKHOUSE_CONTAINER" "$REDIS_CONTAINER"; do
    if [ ! -z "$container" ]; then
        STATUS=$(docker inspect -f '{{.State.Status}}' $container 2>/dev/null)
        HEALTH=$(docker inspect -f '{{.State.Health.Status}}' $container 2>/dev/null || echo "no healthcheck")
        printf "  %-50s %s (%s)\n" "${container:0:50}:" "$STATUS" "$HEALTH"
    fi
done

# Show final workspace
echo ""
echo "Workspace Configuration:"
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT name, type, status FROM \"Workspace\";" 2>/dev/null

# Cloudflare configuration
echo ""
echo "Cloudflare Tunnel Configuration:"
echo "  communication-api.caramelme.com → http://${API_IP}:3001"
echo "  communication-dashboard.caramelme.com → http://${DASHBOARD_IP}:3000"

# Save configuration
cat > /tmp/dittofeed-network-config.txt << EOF
Dittofeed Network Configuration - $(date)
==========================================
API: http://${API_IP}:3001
Dashboard: http://${DASHBOARD_IP}:3000
Postgres: ${POSTGRES_IP}:5432
Temporal: ${TEMPORAL_IP}:7233
ClickHouse: http://${CLICKHOUSE_IP}:8123
Redis: ${REDIS_IP}:6379

Cloudflare Tunnel:
- communication-api.caramelme.com → http://${API_IP}:3001
- communication-dashboard.caramelme.com → http://${DASHBOARD_IP}:3000

Containers:
- API: $API_CONTAINER
- Dashboard: $DASHBOARD_CONTAINER
- Worker: $WORKER_CONTAINER
- Postgres: $POSTGRES_CONTAINER
- Temporal: $TEMPORAL_CONTAINER
- ClickHouse: $CLICKHOUSE_CONTAINER
- Redis: $REDIS_CONTAINER
EOF

echo ""
echo "Configuration saved to: /tmp/dittofeed-network-config.txt"
echo ""
echo "Access URL: https://communication-dashboard.caramelme.com"

if [ "$IP_CHANGED" = "true" ]; then
    echo ""
    echo "⚠️  Remember to update Cloudflare tunnel with the new IPs shown above!"
fi