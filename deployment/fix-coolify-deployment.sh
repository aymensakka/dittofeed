#!/bin/bash
# Fix Coolify deployment issues

echo "=== Fixing Coolify Deployment ==="
echo ""

# Step 1: Clean up old containers
echo "1. Cleaning up old containers..."
docker stop dittofeed-postgres-1 dittofeed-cloudflared-1 2>/dev/null || true
docker rm dittofeed-postgres-1 dittofeed-cloudflared-1 2>/dev/null || true
docker stop $(docker ps -aq -f name=dittofeed-) 2>/dev/null || true
docker rm $(docker ps -aq -f name=dittofeed-) 2>/dev/null || true

echo ""
echo "2. Checking service logs for errors..."
echo "-----------------------------------"

# Check API logs
API_CONTAINER=$(docker ps -q -f name="api-p0gcsc088cogco0cokco4404" | head -1)
if [ -n "$API_CONTAINER" ]; then
    echo "API Logs:"
    docker logs --tail 20 $API_CONTAINER 2>&1 | grep -E "error|Error|ERROR|failed|Failed"
    echo "---"
fi

# Check Worker logs
WORKER_CONTAINER=$(docker ps -q -f name="worker-p0gcsc088cogco0cokco4404" | head -1)
if [ -n "$WORKER_CONTAINER" ]; then
    echo "Worker Logs:"
    docker logs --tail 20 $WORKER_CONTAINER 2>&1 | grep -E "error|Error|ERROR|failed|Failed"
    echo "---"
fi

echo ""
echo "3. Testing database connectivity..."
echo "-----------------------------------"
POSTGRES_CONTAINER=$(docker ps -q -f name="postgres-p0gcsc088cogco0cokco4404" | head -1)
if [ -n "$POSTGRES_CONTAINER" ]; then
    echo -n "PostgreSQL 'dittofeed' database: "
    if docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT 1" >/dev/null 2>&1; then
        echo "✅ Exists"
    else
        echo "❌ Missing - Creating..."
        docker exec $POSTGRES_CONTAINER psql -U postgres -c "CREATE DATABASE dittofeed;" 2>/dev/null || echo "Failed to create"
        docker exec $POSTGRES_CONTAINER psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE dittofeed TO dittofeed;" 2>/dev/null || true
    fi
fi

echo ""
echo "4. Checking network connectivity..."
echo "-----------------------------------"
# Get the network name
NETWORK=$(docker inspect $(docker ps -q -f name="api-p0gcsc088cogco0cokco4404" | head -1) 2>/dev/null | grep -A 5 '"Networks"' | grep '"Name"' | head -1 | cut -d'"' -f4)
echo "Network: $NETWORK"

# Check if cloudflared is in the same network
CLOUDFLARED_CONTAINER=$(docker ps -q -f name="cloudflared-p0gcsc088cogco0cokco4404" | head -1)
if [ -n "$CLOUDFLARED_CONTAINER" ]; then
    CLOUDFLARED_NETWORK=$(docker inspect $CLOUDFLARED_CONTAINER 2>/dev/null | grep -A 5 '"Networks"' | grep '"Name"' | head -1 | cut -d'"' -f4)
    echo "Cloudflared network: $CLOUDFLARED_NETWORK"
    
    if [ "$NETWORK" != "$CLOUDFLARED_NETWORK" ]; then
        echo "❌ Network mismatch! Containers are in different networks"
    else
        echo "✅ All containers in same network"
    fi
fi

echo ""
echo "5. Restarting unhealthy services..."
echo "-----------------------------------"
# Restart unhealthy services
docker restart $(docker ps -q -f name="api-p0gcsc088cogco0cokco4404") 2>/dev/null || true
docker restart $(docker ps -q -f name="worker-p0gcsc088cogco0cokco4404") 2>/dev/null || true

echo ""
echo "=== NEXT STEPS ==="
echo ""
echo "1. Update Cloudflare tunnel routes to use FULL container names:"
echo "   - api.com.caramelme.com → http://api-p0gcsc088cogco0cokco4404-084507720922:3001"
echo "   - dashboard.com.caramelme.com → http://dashboard-p0gcsc088cogco0cokco4404-084507755817:3000"
echo ""
echo "2. Or use the service aliases if the containers are in the same network"
echo ""
echo "3. Check if all services are healthy after restart:"
echo "   docker ps | grep p0gcsc088cogco0cokco4404"