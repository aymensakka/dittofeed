#!/bin/bash

# ==============================================================================
# Check and Fix Container Status for Dittofeed Multi-Tenant
# ==============================================================================

set -e

echo "===================================================="
echo "Checking and Fixing Container Status"
echo "===================================================="

PROJECT_ID="p0gcsc088cogco0cokco4404"

echo "Step 1: Checking all containers for project $PROJECT_ID..."
echo ""

# Show all containers (including stopped ones)
echo "All containers (including stopped):"
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.State}}' | grep "${PROJECT_ID}" || echo "No containers found"

echo ""
echo "Step 2: Checking for stopped containers..."
STOPPED_CONTAINERS=$(docker ps -a --filter "status=exited" --format '{{.Names}}' | grep "${PROJECT_ID}" || true)

if [ ! -z "$STOPPED_CONTAINERS" ]; then
    echo "Found stopped containers:"
    echo "$STOPPED_CONTAINERS"
    echo ""
    echo "Checking logs for stopped containers..."
    
    for container in $STOPPED_CONTAINERS; do
        echo ""
        echo "Logs for $container (last 20 lines):"
        docker logs $container --tail 20 2>&1 || echo "Could not get logs"
        echo "---"
    done
    
    echo ""
    echo "Attempting to restart stopped containers..."
    for container in $STOPPED_CONTAINERS; do
        echo "Starting $container..."
        docker start $container || echo "Failed to start $container"
    done
    
    echo ""
    echo "Waiting for containers to stabilize..."
    sleep 10
fi

echo ""
echo "Step 3: Current running containers:"
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep "${PROJECT_ID}"

echo ""
echo "Step 4: Checking critical services..."

# Find containers
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
WORKER_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "worker.*${PROJECT_ID}" | head -1)
TEMPORAL_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "temporal.*${PROJECT_ID}" | head -1)

echo "Critical services status:"
echo "  API: ${API_CONTAINER:-NOT RUNNING}"
echo "  Postgres: ${POSTGRES_CONTAINER:-NOT RUNNING}"
echo "  Dashboard: ${DASHBOARD_CONTAINER:-NOT RUNNING}"
echo "  Worker: ${WORKER_CONTAINER:-NOT RUNNING}"
echo "  Temporal: ${TEMPORAL_CONTAINER:-NOT RUNNING}"

if [ -z "$API_CONTAINER" ]; then
    echo ""
    echo "⚠️  API container is not running!"
    echo ""
    echo "Checking for API container in stopped state..."
    STOPPED_API=$(docker ps -a --filter "status=exited" --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
    
    if [ ! -z "$STOPPED_API" ]; then
        echo "Found stopped API container: $STOPPED_API"
        echo ""
        echo "Last 30 lines of API logs:"
        docker logs $STOPPED_API --tail 30 2>&1
        echo ""
        echo "Attempting to start API container..."
        docker start $STOPPED_API
        sleep 5
        
        # Check if it's running now
        if docker ps --format '{{.Names}}' | grep -q "$STOPPED_API"; then
            echo "✓ API container started successfully"
        else
            echo "✗ API container failed to start"
            echo ""
            echo "Checking detailed error:"
            docker logs $STOPPED_API --tail 50 2>&1
        fi
    else
        echo "No stopped API container found. It may need to be deployed/created."
    fi
fi

if [ -z "$WORKER_CONTAINER" ]; then
    echo ""
    echo "⚠️  Worker container is not running!"
    echo ""
    echo "Checking for Worker container in stopped state..."
    STOPPED_WORKER=$(docker ps -a --filter "status=exited" --format '{{.Names}}' | grep -E "worker.*${PROJECT_ID}" | head -1)
    
    if [ ! -z "$STOPPED_WORKER" ]; then
        echo "Found stopped Worker container: $STOPPED_WORKER"
        echo "Attempting to start Worker container..."
        docker start $STOPPED_WORKER
        sleep 5
        
        if docker ps --format '{{.Names}}' | grep -q "$STOPPED_WORKER"; then
            echo "✓ Worker container started successfully"
        else
            echo "✗ Worker container failed to start"
        fi
    fi
fi

echo ""
echo "Step 5: Final status check..."
echo ""

# Re-check running containers
echo "Currently running containers:"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | head -1
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep "${PROJECT_ID}"

echo ""
echo "===================================================="
echo "Container Check Complete"
echo "===================================================="
echo ""

# Final check for critical services
API_RUNNING=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
WORKER_RUNNING=$(docker ps --format '{{.Names}}' | grep -E "worker.*${PROJECT_ID}" | head -1)

if [ -z "$API_RUNNING" ] || [ -z "$WORKER_RUNNING" ]; then
    echo "⚠️  ATTENTION: Critical services are not running!"
    echo ""
    echo "This could be due to:"
    echo "1. Deployment issues in Coolify"
    echo "2. Configuration errors"
    echo "3. Resource constraints"
    echo ""
    echo "Recommended actions:"
    echo "1. Check Coolify dashboard for deployment status"
    echo "2. Redeploy the services in Coolify"
    echo "3. Check server resources (disk, memory)"
    echo ""
    echo "To check resources:"
    echo "  df -h    # Check disk space"
    echo "  free -h  # Check memory"
    echo "  docker system df  # Check Docker space"
else
    echo "✓ All critical services are running"
    echo ""
    echo "You can now run the bootstrap script:"
    echo "  ./deployment/bootstrap-with-network-fix.sh"
fi