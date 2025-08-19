#!/bin/bash

echo "======================================"
echo "Starting Dittofeed Containers"
echo "======================================"
echo ""

PROJECT_ID="p0gcsc088cogco0cokco4404"

echo "Starting containers in dependency order..."
echo ""

# Start temporal first (depends on postgres which is already running)
TEMPORAL=$(docker ps -a --format '{{.Names}}' | grep "temporal.*$PROJECT_ID" | head -1)
if [ ! -z "$TEMPORAL" ]; then
    echo "Starting Temporal: $TEMPORAL"
    docker start $TEMPORAL
    sleep 5
fi

# Start API
API=$(docker ps -a --format '{{.Names}}' | grep "api.*$PROJECT_ID" | head -1)
if [ ! -z "$API" ]; then
    echo "Starting API: $API"
    docker start $API
    sleep 3
fi

# Start Worker
WORKER=$(docker ps -a --format '{{.Names}}' | grep "worker.*$PROJECT_ID" | head -1)
if [ ! -z "$WORKER" ]; then
    echo "Starting Worker: $WORKER"
    docker start $WORKER
    sleep 3
fi

# Start Dashboard
DASHBOARD=$(docker ps -a --format '{{.Names}}' | grep "dashboard.*$PROJECT_ID" | head -1)
if [ ! -z "$DASHBOARD" ]; then
    echo "Starting Dashboard: $DASHBOARD"
    docker start $DASHBOARD
    sleep 3
fi

echo ""
echo "Waiting for services to initialize..."
sleep 10

echo ""
echo "Current container status:"
echo "--------------------------"
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep $PROJECT_ID

echo ""
echo "Checking service health:"
echo "------------------------"

# Check API health
API_RUNNING=$(docker ps --format '{{.Names}}' | grep "api.*$PROJECT_ID" | head -1)
if [ ! -z "$API_RUNNING" ]; then
    API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_RUNNING 2>/dev/null | head -c -1)
    echo -n "API Health: "
    docker exec $API_RUNNING curl -s "http://localhost:3001/health" 2>/dev/null || echo "Not ready yet"
fi

echo ""
echo "======================================"
echo "Container Startup Complete"
echo "======================================"
echo ""
echo "If containers fail to start, check logs with:"
echo "docker logs <container-name> --tail 50"
echo ""
echo "To apply the dashboard fix, run:"
echo "./deployment/fix-now.sh"