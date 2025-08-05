#!/bin/bash
# Manually start Dittofeed services

echo "=== Starting Dittofeed Services Manually ==="
echo ""

# First, remove the created but not started containers
echo "1. Removing created containers..."
docker rm dittofeed_api dittofeed_dashboard dittofeed_worker 2>/dev/null || true

echo ""
echo "2. Starting services with docker-compose..."
docker compose -f docker-compose.coolify.yaml up -d

echo ""
echo "3. Waiting for services to start..."
sleep 5

echo ""
echo "4. Checking container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "postgres|redis|api|worker|dashboard|cloudflared"

echo ""
echo "5. Checking for errors in logs:"
echo "-----------------------------------"
for service in postgres redis api dashboard worker; do
    container=$(docker ps -aq -f name=dittofeed_$service | head -1)
    if [ -n "$container" ]; then
        echo "Logs for $service:"
        docker logs --tail 10 $container 2>&1 | head -20
        echo "---"
    fi
done

echo ""
echo "6. Testing connectivity:"
echo "-----------------------------------"
# Test if services can reach each other
api_container=$(docker ps -q -f name=api | head -1)
if [ -n "$api_container" ]; then
    echo -n "API health check: "
    if docker exec $api_container wget -q -O- http://localhost:3001/health 2>/dev/null; then
        echo "✅ OK"
    else
        echo "❌ Failed"
    fi
fi

echo ""
echo "If services fail to start, check:"
echo "1. Environment variables in docker-compose.coolify.yaml"
echo "2. Database connection (DATABASE_URL format)"
echo "3. Container logs for specific errors"