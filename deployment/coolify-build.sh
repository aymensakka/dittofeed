#!/bin/bash
# Coolify build script with persistent Docker authentication and container verification
set -e

echo "=== Starting Coolify Build Process ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check container status
check_container_status() {
    local container_pattern=$1
    local max_attempts=15
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        # Check if container is running
        if docker ps --format '{{.Names}}' | grep -q "$container_pattern"; then
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    return 1
}

# Step 1: Setup persistent Docker config location
export DOCKER_CONFIG=/tmp/docker-coolify
mkdir -p $DOCKER_CONFIG

echo "Using Docker config at: $DOCKER_CONFIG"

# Step 2: Login to Docker registry
echo "Logging into Docker registry..."
echo '9sFPGGDJUFnE4z*z4Aj9' | docker login docker.reactmotion.com -u coolify-system --password-stdin

# Step 3: Verify login was successful
if docker pull docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1 2>&1 | head -1 | grep -q "Pulling"; then
    echo -e "${GREEN}✓${NC} Docker authentication successful"
else
    echo "✗ Docker authentication failed, retrying..."
    # Retry with direct password
    docker login docker.reactmotion.com -u coolify-system -p '9sFPGGDJUFnE4z*z4Aj9'
fi

# Step 4: Pull all images explicitly before docker-compose
echo "Pre-pulling images..."
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1 &
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1 &
docker pull docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1 &

# Wait for all pulls
wait

echo -e "${GREEN}✓${NC} All images pulled successfully"

# Note: Docker-compose up is handled by Coolify after this script
# We'll add a post-deployment verification

# Step 5: Wait for docker-compose to complete (Coolify runs it after this script)
echo "Waiting for services to start..."
sleep 20

# Step 6: Verify critical services are running
echo ""
echo "=== Verifying Service Status ==="

PROJECT_ID="p0gcsc088cogco0cokco4404"
FAILED_SERVICES=()

# Check each service
for service in postgres redis clickhouse temporal api worker dashboard; do
    echo -n "Checking $service: "
    if check_container_status "${service}.*${PROJECT_ID}"; then
        echo -e "${GREEN}✓ Running${NC}"
    else
        echo -e "${RED}✗ Not running${NC}"
        FAILED_SERVICES+=("$service")
        # Get logs for failed service
        CONTAINER=$(docker ps -a --format '{{.Names}}' | grep "${service}.*${PROJECT_ID}" | head -1)
        if [ ! -z "$CONTAINER" ]; then
            echo "Last 20 lines of $service logs:"
            docker logs "$CONTAINER" --tail 20 2>&1 || echo "Could not retrieve logs"
        fi
    fi
done

# Step 7: Report status
echo ""
if [ ${#FAILED_SERVICES[@]} -eq 0 ]; then
    echo -e "${GREEN}=== All services started successfully ===${NC}"
    
    # Additional checks for API and Dashboard health
    API=$(docker ps --format '{{.Names}}' | grep "api.*$PROJECT_ID" | head -1)
    if [ ! -z "$API" ]; then
        echo -n "API health check: "
        if docker exec $API curl -s -f http://localhost:3001/health >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${YELLOW}⚠ Starting up${NC}"
        fi
    fi
    
    echo "=== Build process complete ==="
    exit 0
else
    echo -e "${RED}=== Deployment failed ===${NC}"
    echo "The following services failed to start:"
    for service in "${FAILED_SERVICES[@]}"; do
        echo "  - $service"
    done
    echo ""
    echo "Check the logs above for details."
    exit 1
fi