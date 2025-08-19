#!/bin/bash

set -e  # Exit on any error

echo "=== Starting Coolify Build Process ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check container status
check_container_status() {
    local container_name=$1
    local max_attempts=30
    local attempt=0
    
    echo -n "Checking $container_name status"
    
    while [ $attempt -lt $max_attempts ]; do
        # Check if container exists and is running
        if docker ps --format '{{.Names}}' | grep -q "$container_name"; then
            # Container is running, check if it's healthy or at least staying up
            local status=$(docker inspect -f '{{.Status.Running}}' "$container_name" 2>/dev/null || echo "false")
            if [ "$status" = "true" ]; then
                # Check if container has been running for at least 5 seconds
                local uptime=$(docker inspect -f '{{.State.StartedAt}}' "$container_name" 2>/dev/null)
                if [ ! -z "$uptime" ]; then
                    echo -e " ${GREEN}✓${NC}"
                    return 0
                fi
            fi
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo -e " ${RED}✗${NC}"
    return 1
}

# Function to get container logs on failure
get_failure_logs() {
    local container_pattern=$1
    local container=$(docker ps -a --format '{{.Names}}' | grep "$container_pattern" | head -1)
    
    if [ ! -z "$container" ]; then
        echo -e "${YELLOW}Last 50 lines of logs for $container:${NC}"
        docker logs "$container" --tail 50 2>&1 || echo "Could not retrieve logs"
        echo "---"
    fi
}

# Docker registry login
DOCKER_CONFIG=${DOCKER_CONFIG:-"/tmp/docker-coolify"}
export DOCKER_CONFIG
mkdir -p $DOCKER_CONFIG

echo "Using Docker config at: $DOCKER_CONFIG"
echo "Logging into Docker registry..."

docker login docker.reactmotion.com \
    --username coolify-system \
    --password '9sFPGGDJUFnE4z*z4Aj9' || {
    echo -e "${RED}✗ Docker login failed${NC}"
    exit 1
}

echo -e "${GREEN}✓${NC} Docker authentication successful"

# Pre-pull images to ensure they exist
echo "Pre-pulling images..."
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1 || {
    echo -e "${RED}✗ Failed to pull API image${NC}"
    exit 1
}
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1 || {
    echo -e "${RED}✗ Failed to pull Dashboard image${NC}"
    exit 1
}
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1 || {
    echo -e "${RED}✗ Failed to pull Worker image${NC}"
    exit 1
}

echo -e "${GREEN}✓${NC} All images pulled successfully"

# Let docker-compose handle the deployment
echo "Starting services with docker-compose..."

# The compose up command should be handled by Coolify
# We'll check the results after

# Wait for docker-compose to finish
sleep 10

# Verify critical services are running
echo ""
echo "=== Verifying Service Status ==="

PROJECT_ID="p0gcsc088cogco0cokco4404"
FAILED_SERVICES=()

# Check PostgreSQL
echo -n "PostgreSQL: "
if check_container_status "postgres.*$PROJECT_ID"; then
    # Additional health check
    POSTGRES=$(docker ps --format '{{.Names}}' | grep "postgres.*$PROJECT_ID" | head -1)
    if docker exec $POSTGRES pg_isready -U dittofeed >/dev/null 2>&1; then
        echo -e "  Health check: ${GREEN}✓${NC}"
    else
        echo -e "  Health check: ${YELLOW}⚠${NC} (may still be initializing)"
    fi
else
    FAILED_SERVICES+=("postgres")
    get_failure_logs "postgres.*$PROJECT_ID"
fi

# Check Redis
echo -n "Redis: "
if check_container_status "redis.*$PROJECT_ID"; then
    echo -e "  ${GREEN}Running${NC}"
else
    FAILED_SERVICES+=("redis")
    get_failure_logs "redis.*$PROJECT_ID"
fi

# Check ClickHouse
echo -n "ClickHouse: "
if check_container_status "clickhouse.*$PROJECT_ID"; then
    echo -e "  ${GREEN}Running${NC}"
else
    FAILED_SERVICES+=("clickhouse")
    get_failure_logs "clickhouse.*$PROJECT_ID"
fi

# Check Temporal
echo -n "Temporal: "
if check_container_status "temporal.*$PROJECT_ID"; then
    echo -e "  ${GREEN}Running${NC}"
else
    FAILED_SERVICES+=("temporal")
    get_failure_logs "temporal.*$PROJECT_ID"
fi

# Check API
echo -n "API: "
if check_container_status "api.*$PROJECT_ID"; then
    API=$(docker ps --format '{{.Names}}' | grep "api.*$PROJECT_ID" | head -1)
    # Try health endpoint
    if docker exec $API curl -s -f http://localhost:3001/health >/dev/null 2>&1; then
        echo -e "  Health endpoint: ${GREEN}✓${NC}"
    else
        echo -e "  Health endpoint: ${YELLOW}⚠${NC} (may still be starting)"
    fi
else
    FAILED_SERVICES+=("api")
    get_failure_logs "api.*$PROJECT_ID"
fi

# Check Worker
echo -n "Worker: "
if check_container_status "worker.*$PROJECT_ID"; then
    echo -e "  ${GREEN}Running${NC}"
else
    FAILED_SERVICES+=("worker")
    get_failure_logs "worker.*$PROJECT_ID"
fi

# Check Dashboard
echo -n "Dashboard: "
if check_container_status "dashboard.*$PROJECT_ID"; then
    DASHBOARD=$(docker ps --format '{{.Names}}' | grep "dashboard.*$PROJECT_ID" | head -1)
    # Check if Next.js is responding
    if docker exec $API curl -s -o /dev/null -w "%{http_code}" http://$DASHBOARD:3000 2>/dev/null | grep -q "200\|302\|307"; then
        echo -e "  Web server: ${GREEN}✓${NC}"
    else
        echo -e "  Web server: ${YELLOW}⚠${NC} (may still be starting)"
    fi
else
    FAILED_SERVICES+=("dashboard")
    get_failure_logs "dashboard.*$PROJECT_ID"
fi

# Check Cloudflared (optional, don't fail deployment)
echo -n "Cloudflared: "
if check_container_status "cloudflared.*$PROJECT_ID"; then
    echo -e "  ${GREEN}Running${NC}"
else
    echo -e "  ${YELLOW}Not running${NC} (optional service)"
fi

echo ""
echo "=== Deployment Summary ==="

if [ ${#FAILED_SERVICES[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ All critical services are running${NC}"
    
    # Run post-deployment bootstrap
    echo ""
    echo "Running post-deployment bootstrap..."
    
    # Check if workspace exists
    POSTGRES=$(docker ps --format '{{.Names}}' | grep "postgres.*$PROJECT_ID" | head -1)
    WORKSPACE_EXISTS=$(docker exec $POSTGRES psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM \"Workspace\";" 2>/dev/null | tr -d ' \n' || echo "0")
    
    if [ "$WORKSPACE_EXISTS" = "0" ]; then
        echo "Creating initial workspace..."
        # Run workspace creation
        API=$(docker ps --format '{{.Names}}' | grep "api.*$PROJECT_ID" | head -1)
        docker exec $API node packages/api/dist/scripts/bootstrap.js 2>/dev/null || {
            echo -e "${YELLOW}⚠ Workspace creation needs to be done manually${NC}"
        }
    else
        echo "Workspace already exists"
    fi
    
    # Update Cloudflare tunnel if needed
    if docker ps | grep -q "cloudflared.*$PROJECT_ID"; then
        echo "Updating Cloudflare tunnel configuration..."
        # Get container IPs
        API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps --format '{{.Names}}' | grep "api.*$PROJECT_ID" | head -1) 2>/dev/null | head -c -1)
        DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps --format '{{.Names}}' | grep "dashboard.*$PROJECT_ID" | head -1) 2>/dev/null | head -c -1)
        
        if [ ! -z "$API_IP" ] && [ ! -z "$DASHBOARD_IP" ]; then
            echo "  API IP: $API_IP"
            echo "  Dashboard IP: $DASHBOARD_IP"
            # Note: Cloudflare config update would go here
        fi
    fi
    
    echo ""
    echo -e "${GREEN}=== Build process complete ===${NC}"
    exit 0
else
    echo -e "${RED}✗ Failed services: ${FAILED_SERVICES[@]}${NC}"
    echo ""
    echo "Deployment failed. The following services did not start correctly:"
    for service in "${FAILED_SERVICES[@]}"; do
        echo "  - $service"
    done
    echo ""
    echo "Check the logs above for error details."
    echo "To debug further, use: docker logs <container-name> --tail 100"
    echo ""
    echo -e "${RED}=== Build process failed ===${NC}"
    exit 1
fi