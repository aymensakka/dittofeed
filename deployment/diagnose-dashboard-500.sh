#!/bin/bash

# ==============================================================================
# Diagnose Dashboard 500 Error on Journeys Page
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}Diagnosing Dashboard 500 Error${NC}"
echo -e "${BLUE}===================================================${NC}"

# Find containers
DASHBOARD_CONTAINER=$(docker ps | grep dashboard | head -1 | awk '{print $1}')
API_CONTAINER=$(docker ps | grep "api-" | head -1 | awk '{print $1}')
POSTGRES_CONTAINER=$(docker ps | grep postgres | grep -v supabase | head -1 | awk '{print $1}')

echo -e "\n${BLUE}Step 1: Container Status${NC}"
echo "Dashboard: $DASHBOARD_CONTAINER"
echo "API: $API_CONTAINER"
echo "PostgreSQL: $POSTGRES_CONTAINER"

echo -e "\n${BLUE}Step 2: Dashboard Error Logs${NC}"
echo "Recent errors from dashboard:"
docker logs "$DASHBOARD_CONTAINER" 2>&1 | grep -i error | tail -10 || echo "No recent errors in logs"

echo -e "\n${BLUE}Step 3: Full Dashboard Logs (last 30 lines)${NC}"
docker logs "$DASHBOARD_CONTAINER" --tail 30

echo -e "\n${BLUE}Step 4: Dashboard Environment Check${NC}"
echo "Key environment variables:"
docker exec "$DASHBOARD_CONTAINER" env | grep -E "(AUTH_MODE|API_BASE_URL|DATABASE_URL|GOOGLE|NEXTAUTH_URL|MULTITENANCY)" | sort

echo -e "\n${BLUE}Step 5: API Health Check${NC}"
# Check if API is healthy
API_HEALTH=$(docker inspect "$API_CONTAINER" --format='{{.State.Health.Status}}' 2>/dev/null || echo "no health check")
echo "API container health: $API_HEALTH"

# Get API IP
CLOUDFLARED_NETWORK=$(docker inspect $(docker ps | grep cloudflared | head -1 | awk '{print $1}') --format='{{range $key, $value := .NetworkSettings.Networks}}{{$key}}{{end}}' | head -1)
API_IP=$(docker inspect "$API_CONTAINER" -f "{{.NetworkSettings.Networks.$CLOUDFLARED_NETWORK.IPAddress}}")

# Test API endpoints
echo -e "\n${BLUE}Testing API endpoints:${NC}"
echo -n "  /api endpoint: "
curl -sf "http://$API_IP:3001/api" && echo -e "${GREEN}✓ Working${NC}" || echo -e "${RED}✗ Failed${NC}"

echo -n "  /health endpoint: "
curl -sf "http://$API_IP:3001/health" && echo -e "${GREEN}✓ Working${NC}" || echo -e "${RED}✗ Failed${NC}"

echo -e "\n${BLUE}Step 6: Database Connectivity${NC}"
# Check database tables
TABLE_COUNT=$(docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d dittofeed -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
echo "Database tables: $TABLE_COUNT"

# Check for workspace table
echo -n "Workspace table exists: "
docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d dittofeed -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'workspace');" 2>/dev/null | grep -q 't' && echo -e "${GREEN}✓ Yes${NC}" || echo -e "${RED}✗ No${NC}"

# Check for any workspaces
WORKSPACE_COUNT=$(docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d dittofeed -tAc "SELECT COUNT(*) FROM workspace;" 2>/dev/null || echo "0")
echo "Number of workspaces: $WORKSPACE_COUNT"

echo -e "\n${BLUE}Step 7: Test Dashboard Internal Connectivity${NC}"
# Test if dashboard can reach API
echo -n "Dashboard can reach API: "
docker exec "$DASHBOARD_CONTAINER" sh -c "curl -sf http://$API_IP:3001/api > /dev/null 2>&1" && echo -e "${GREEN}✓ Yes${NC}" || echo -e "${RED}✗ No${NC}"

echo -e "\n${BLUE}Step 8: Session and Auth Check${NC}"
# Check for session-related errors
echo "Checking for session/auth errors in logs:"
docker logs "$DASHBOARD_CONTAINER" 2>&1 | grep -E "(session|auth|jwt|token)" | tail -5 || echo "No auth-related messages"

echo -e "\n${BLUE}Step 9: Network Connectivity${NC}"
# Show network configuration
DASHBOARD_IP=$(docker inspect "$DASHBOARD_CONTAINER" -f "{{.NetworkSettings.Networks.$CLOUDFLARED_NETWORK.IPAddress}}")
echo "Dashboard IP on tunnel network: $DASHBOARD_IP"
echo "API IP on tunnel network: $API_IP"

echo -e "\n${BLUE}Step 10: Recommendations${NC}"
echo -e "${YELLOW}Based on the diagnostics:${NC}"

if [ "$TABLE_COUNT" -eq "0" ]; then
    echo -e "${RED}• Database is not initialized. Run the database initialization script.${NC}"
fi

if [ "$WORKSPACE_COUNT" -eq "0" ]; then
    echo -e "${YELLOW}• No workspaces exist. This might be normal for a fresh installation.${NC}"
    echo "  You may need to create an initial workspace through the API or dashboard."
fi

# Check if dashboard can reach API
if ! docker exec "$DASHBOARD_CONTAINER" sh -c "curl -sf http://$API_IP:3001/api > /dev/null 2>&1"; then
    echo -e "${RED}• Dashboard cannot reach API. Network configuration issue.${NC}"
fi

echo -e "\n${GREEN}===================================================${NC}"
echo -e "${GREEN}Diagnostics Complete${NC}"
echo -e "${GREEN}===================================================${NC}"