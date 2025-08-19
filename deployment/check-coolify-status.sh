#!/bin/bash
# Check Coolify deployment status

echo "=== Coolify Deployment Status Check ==="
echo "Time: $(date)"
echo ""

# Check running containers
echo "1. Running containers for Dittofeed:"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -E "api|dashboard|worker|postgres|redis|clickhouse|temporal" || echo "   No Dittofeed containers running"

echo ""
echo "2. Recent container events:"
docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | head -10

echo ""
echo "3. Checking API container logs:"
API_CONTAINER=$(docker ps -q -f "name=api")
if [ -n "$API_CONTAINER" ]; then
    echo "   API container ID: $API_CONTAINER"
    docker logs --tail 20 $API_CONTAINER 2>&1
else
    echo "   API container not running"
    # Check if it exists but stopped
    API_STOPPED=$(docker ps -aq -f "name=api" | head -1)
    if [ -n "$API_STOPPED" ]; then
        echo "   Found stopped API container, last logs:"
        docker logs --tail 20 $API_STOPPED 2>&1
    fi
fi

echo ""
echo "4. Checking Dashboard container logs:"
DASHBOARD_CONTAINER=$(docker ps -q -f "name=dashboard")
if [ -n "$DASHBOARD_CONTAINER" ]; then
    echo "   Dashboard container ID: $DASHBOARD_CONTAINER"
    docker logs --tail 20 $DASHBOARD_CONTAINER 2>&1
else
    echo "   Dashboard container not running"
    # Check if it exists but stopped
    DASH_STOPPED=$(docker ps -aq -f "name=dashboard" | head -1)
    if [ -n "$DASH_STOPPED" ]; then
        echo "   Found stopped Dashboard container, last logs:"
        docker logs --tail 20 $DASH_STOPPED 2>&1
    fi
fi

echo ""
echo "5. Checking network connectivity:"
# Check if containers can reach each other
echo "   Testing postgres connection:"
docker exec $(docker ps -q -f "name=api" | head -1) nc -zv postgres 5432 2>&1 || echo "   Cannot test postgres connectivity"

echo ""
echo "6. Checking environment variables in API:"
docker exec $(docker ps -q -f "name=api" | head -1) printenv | grep -E "AUTH_MODE|DATABASE_URL|GOOGLE" || echo "   Cannot check env vars"

echo ""
echo "=== Quick Actions ==="
echo "To restart all containers via Coolify:"
echo "  Go to Coolify dashboard and click 'Redeploy'"
echo ""
echo "To check specific container:"
echo "  docker logs -f <container_name>"
echo ""
echo "To restart a specific container:"
echo "  docker restart <container_name>"
