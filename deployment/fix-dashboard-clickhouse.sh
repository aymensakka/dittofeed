#!/bin/bash

# ==============================================================================
# Fix Dashboard ClickHouse Configuration on Coolify Server
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}Fixing Dashboard ClickHouse Configuration${NC}"
echo -e "${BLUE}===================================================${NC}"

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
    echo -e "${GREEN}✓ Loaded environment variables${NC}"
else
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi

# Expand the tilde in SSH_KEY_PATH
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

# Function to run SSH commands
run_ssh() {
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "$1"
}

echo -e "\n${YELLOW}Finding dashboard container...${NC}"
DASHBOARD_CONTAINER=$(run_ssh "docker ps -a --format '{{.Names}}' | grep -E 'dashboard.*${COOLIFY_PROJECT_ID}' | head -1")

if [ -z "$DASHBOARD_CONTAINER" ]; then
    echo -e "${RED}✗ Dashboard container not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found dashboard container: $DASHBOARD_CONTAINER${NC}"

# Stop the current dashboard container
echo -e "\n${YELLOW}Stopping current dashboard container...${NC}"
run_ssh "docker stop $DASHBOARD_CONTAINER || true"

# Remove the current dashboard container
echo -e "\n${YELLOW}Removing current dashboard container...${NC}"
run_ssh "docker rm $DASHBOARD_CONTAINER || true"

# Get the network name
echo -e "\n${YELLOW}Getting network configuration...${NC}"
NETWORK_NAME="${COOLIFY_PROJECT_ID}"

# Create new dashboard container with all environment variables
echo -e "\n${YELLOW}Creating new dashboard container with ClickHouse configuration...${NC}"
run_ssh "docker run -d \
  --name $DASHBOARD_CONTAINER \
  --network $NETWORK_NAME \
  --restart unless-stopped \
  -e NODE_ENV=production \
  -e NEXTAUTH_URL=https://communication-dashboard.caramelme.com \
  -e NEXTAUTH_SECRET=your_nextauth_secret_here \
  -e API_BASE_URL=http://172.27.0.10:3001 \
  -e DATABASE_URL=postgresql://dittofeed:${POSTGRES_PASSWORD}@postgres:5432/dittofeed \
  -e DATABASE_HOST=postgres \
  -e DATABASE_PASSWORD=${POSTGRES_PASSWORD} \
  -e DATABASE_USER=dittofeed \
  -e DATABASE_NAME=dittofeed \
  -e AUTH_MODE=multi-tenant \
  -e MULTITENANCY_ENABLED=true \
  -e ENABLE_WORKSPACE_QUOTA=true \
  -e NEXT_PUBLIC_API_BASE_URL=https://communication-api.caramelme.com \
  -e NEXT_PUBLIC_AUTH_MODE=multi-tenant \
  -e CLICKHOUSE_HOST=clickhouse-${COOLIFY_PROJECT_ID} \
  -e CLICKHOUSE_PORT=8123 \
  -e CLICKHOUSE_USER=dittofeed \
  -e CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD} \
  -e CLICKHOUSE_DATABASE=dittofeed \
  -e TEMPORAL_ADDRESS=temporal-${COOLIFY_PROJECT_ID}:7233 \
  -e TEMPORAL_NAMESPACE=default \
  -e AUTH_PROVIDER=google \
  -e GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID} \
  -e GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET} \
  docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1"

# Wait for container to start
echo -e "\n${YELLOW}Waiting for dashboard to start...${NC}"
sleep 10

# Check container status
echo -e "\n${YELLOW}Checking container status...${NC}"
CONTAINER_STATUS=$(run_ssh "docker ps --format '{{.Names}}\t{{.Status}}' | grep $DASHBOARD_CONTAINER || echo 'Container not running'")
echo "$CONTAINER_STATUS"

# Check container logs for errors
echo -e "\n${YELLOW}Checking container logs...${NC}"
run_ssh "docker logs $DASHBOARD_CONTAINER --tail 20 2>&1"

# Connect to cloudflared network
echo -e "\n${YELLOW}Connecting to cloudflared network...${NC}"
CLOUDFLARED_NETWORK=$(run_ssh "docker network ls --format '{{.Name}}' | grep cloudflared || echo ''")
if [ ! -z "$CLOUDFLARED_NETWORK" ]; then
    run_ssh "docker network connect $CLOUDFLARED_NETWORK $DASHBOARD_CONTAINER || true"
    echo -e "${GREEN}✓ Connected to cloudflared network${NC}"
fi

# Test dashboard health
echo -e "\n${YELLOW}Testing dashboard health...${NC}"
if run_ssh "curl -s http://172.27.0.11:3000 > /dev/null 2>&1"; then
    echo -e "${GREEN}✓ Dashboard is responding${NC}"
else
    echo -e "${RED}✗ Dashboard not responding${NC}"
fi

# Test external URL
echo -e "\n${YELLOW}Testing external URL...${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://communication-dashboard.caramelme.com)
if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "302" ]; then
    echo -e "${GREEN}✓ Dashboard accessible externally (HTTP $HTTP_CODE)${NC}"
else
    echo -e "${YELLOW}⚠ Dashboard returned HTTP $HTTP_CODE${NC}"
fi

echo -e "\n${GREEN}===================================================${NC}"
echo -e "${GREEN}Dashboard ClickHouse configuration updated!${NC}"
echo -e "${GREEN}===================================================${NC}"
echo ""
echo "Next steps:"
echo "1. Test the dashboard at: https://communication-dashboard.caramelme.com"
echo "2. Check for any remaining errors in the logs"
echo "3. Verify ClickHouse connectivity in the dashboard"