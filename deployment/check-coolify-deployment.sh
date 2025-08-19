#!/bin/bash

echo "======================================"
echo "Checking Coolify Deployment Status"
echo "======================================"
echo ""

PROJECT_ID="p0gcsc088cogco0cokco4404"

echo "1. Running Containers for project $PROJECT_ID:"
echo "----------------------------------------------"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep $PROJECT_ID || echo "No containers found for project"
echo ""

echo "2. All Containers (including stopped):"
echo "---------------------------------------"
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep -E "(dashboard|api|worker|temporal).*$PROJECT_ID" || echo "No Dittofeed containers found"
echo ""

echo "3. Recent Docker Events (last 5 minutes):"
echo "------------------------------------------"
docker events --since 5m --until now --format 'table {{.Time}}\t{{.Action}}\t{{.Actor.Attributes.name}}' | grep -E "(dashboard|api|worker)" | head -20 || echo "No recent events"
echo ""

echo "4. Checking for Failed Containers:"
echo "-----------------------------------"
docker ps -a --filter "status=exited" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep $PROJECT_ID || echo "No exited containers"
echo ""

echo "5. Checking Docker Compose Services:"
echo "-------------------------------------"
# Try to find docker-compose file
COMPOSE_FILE=$(find /data/coolify -name "docker-compose.yml" -o -name "docker-compose.yaml" 2>/dev/null | grep $PROJECT_ID | head -1)

if [ ! -z "$COMPOSE_FILE" ]; then
    echo "Found compose file: $COMPOSE_FILE"
    echo "Services defined:"
    grep "^\s*[a-z]" $COMPOSE_FILE | grep -v "#" | head -20
else
    echo "No docker-compose file found for project"
fi
echo ""

echo "6. Checking Images:"
echo "-------------------"
docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.CreatedSince}}\t{{.Size}}' | grep -E "dittofeed|dashboard|api|worker" | head -10
echo ""

echo "======================================"
echo "Summary:"
echo "======================================"

# Count running services
RUNNING_COUNT=$(docker ps --format '{{.Names}}' | grep $PROJECT_ID | wc -l)
echo "Running containers for project: $RUNNING_COUNT"

if [ "$RUNNING_COUNT" -lt 6 ]; then
    echo ""
    echo "⚠️  WARNING: Expected at least 6 containers (api, dashboard, worker, temporal, postgres, clickhouse, redis)"
    echo ""
    echo "Missing services. Possible issues:"
    echo "1. Deployment failed in Coolify"
    echo "2. Image pull errors"
    echo "3. Configuration issues"
    echo ""
    echo "Actions to try:"
    echo "1. Check Coolify deployment logs"
    echo "2. Redeploy the stack in Coolify"
    echo "3. Check if images are available in registry"
fi

echo ""
echo "To check specific container logs:"
echo "docker logs <container-name> --tail 50"