#!/bin/bash

# ==============================================================================
# Check Coolify Deployment Status
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}Checking Coolify Deployment Status${NC}"
echo -e "${BLUE}===================================================${NC}"

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
    echo -e "${GREEN}✓ Loaded environment variables${NC}"
else
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi

# Validate required variables
if [ -z "$SERVER_IP" ] || [ -z "$SSH_USER" ] || [ -z "$SSH_KEY_PATH" ]; then
    echo -e "${RED}✗ Missing server configuration in .env${NC}"
    echo "Please set: SERVER_IP, SSH_USER, SSH_KEY_PATH"
    exit 1
fi

# Expand the tilde in SSH_KEY_PATH
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

# Check if SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}✗ SSH key not found at: $SSH_KEY_PATH${NC}"
    exit 1
fi

# Function to run SSH commands
run_ssh() {
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "$1"
}

# Check container status
echo -e "\n${YELLOW}Container Status:${NC}"
run_ssh "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E '($COOLIFY_PROJECT_ID|NAME)' || echo 'No containers found'"

# Check specific services
echo -e "\n${YELLOW}Service Health Checks:${NC}"

# PostgreSQL
echo -n "PostgreSQL: "
if run_ssh "docker exec \$(docker ps -q -f name=postgres | grep -m1 .) psql -U dittofeed -d postgres -c 'SELECT 1' > /dev/null 2>&1"; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

# Redis
echo -n "Redis: "
if run_ssh "docker exec \$(docker ps -q -f name=redis | grep -m1 .) redis-cli ping 2>/dev/null | grep -q PONG"; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

# ClickHouse
echo -n "ClickHouse: "
if run_ssh "docker exec \$(docker ps -q -f name=clickhouse | grep -m1 .) clickhouse-client --query 'SELECT 1' > /dev/null 2>&1"; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

# Temporal
echo -n "Temporal: "
TEMPORAL_STATUS=$(run_ssh "docker ps -a --format '{{.Names}}\t{{.Status}}' | grep temporal | grep $COOLIFY_PROJECT_ID | awk '{print \$2}' | head -1" || echo "Not found")
if [[ "$TEMPORAL_STATUS" == *"Up"* ]]; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Status: $TEMPORAL_STATUS${NC}"
fi

# API
echo -n "API: "
if run_ssh "curl -s http://localhost:3001/health > /dev/null 2>&1"; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

# Dashboard
echo -n "Dashboard: "
if run_ssh "curl -s http://localhost:3000 > /dev/null 2>&1"; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not ready${NC}"
fi

# Check recent logs for errors
echo -e "\n${YELLOW}Recent Error Logs:${NC}"
echo "Temporal logs:"
run_ssh "docker logs \$(docker ps -aq -f name=temporal | head -1) 2>&1 | tail -5 | grep -i error || echo 'No recent errors'"

echo "API logs:"
run_ssh "docker logs \$(docker ps -aq -f name=api | head -1) 2>&1 | tail -5 | grep -i error || echo 'No recent errors'"

# Check Cloudflare tunnel status
echo -e "\n${YELLOW}Cloudflare Tunnel Status:${NC}"
TUNNEL_STATUS=$(run_ssh "docker ps --format '{{.Names}}\t{{.Status}}' | grep cloudflared || echo 'Cloudflare tunnel not found'")
echo "$TUNNEL_STATUS"

# Test external URLs
echo -e "\n${YELLOW}External URL Tests:${NC}"
echo -n "Dashboard (https://communication-dashboard.caramelme.com): "
if curl -s -o /dev/null -w "%{http_code}" https://communication-dashboard.caramelme.com | grep -q "200\|302"; then
    echo -e "${GREEN}✓ Accessible${NC}"
else
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://communication-dashboard.caramelme.com)
    echo -e "${RED}✗ HTTP $HTTP_CODE${NC}"
fi

echo -n "API (https://communication-api.caramelme.com): "
if curl -s -o /dev/null -w "%{http_code}" https://communication-api.caramelme.com/health | grep -q "200"; then
    echo -e "${GREEN}✓ Accessible${NC}"
else
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://communication-api.caramelme.com/health)
    echo -e "${RED}✗ HTTP $HTTP_CODE${NC}"
fi

echo -e "\n${GREEN}===================================================${NC}"
echo -e "${GREEN}Status check complete!${NC}"
echo -e "${GREEN}===================================================${NC}"