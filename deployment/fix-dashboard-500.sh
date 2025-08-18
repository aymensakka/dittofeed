#!/bin/bash

# ==============================================================================
# Fix Dashboard 500 Error - Direct Server Script
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

if [ -z "$DASHBOARD_CONTAINER" ]; then
    echo -e "${RED}Dashboard container not found${NC}"
    exit 1
fi

echo -e "\n${BLUE}Step 1: Checking dashboard logs...${NC}"
docker logs "$DASHBOARD_CONTAINER" --tail 20

echo -e "\n${BLUE}Step 2: Checking dashboard environment...${NC}"
docker exec "$DASHBOARD_CONTAINER" env | grep -E "(AUTH_MODE|API_BASE_URL|NEXTAUTH|GOOGLE|DATABASE_URL)" | sort

echo -e "\n${BLUE}Step 3: Testing API connectivity from dashboard...${NC}"
# Test if dashboard can reach API
docker exec "$DASHBOARD_CONTAINER" sh -c 'wget -O- http://api:3001/api 2>/dev/null || curl http://api:3001/api 2>/dev/null' || echo "Failed to reach API via service name"

# Get API IP on the cloudflared network
if [ -n "$API_CONTAINER" ]; then
    CLOUDFLARED_NETWORK=$(docker inspect $(docker ps | grep cloudflared | head -1 | awk '{print $1}') --format='{{range $key, $value := .NetworkSettings.Networks}}{{$key}}{{end}}' | head -1)
    API_IP=$(docker inspect "$API_CONTAINER" -f "{{.NetworkSettings.Networks.$CLOUDFLARED_NETWORK.IPAddress}}")
    echo -e "\n${BLUE}API IP on cloudflared network: $API_IP${NC}"
    
    # Test with IP
    docker exec "$DASHBOARD_CONTAINER" sh -c "wget -O- http://$API_IP:3001/api 2>/dev/null || curl http://$API_IP:3001/api 2>/dev/null" || echo "Failed to reach API via IP"
fi

echo -e "\n${BLUE}Step 4: Creating fixed dashboard with proper config...${NC}"

# Get current dashboard image
DASHBOARD_IMAGE=$(docker inspect "$DASHBOARD_CONTAINER" --format='{{.Config.Image}}')
echo "Using image: $DASHBOARD_IMAGE"

# Stop current dashboard
docker stop "$DASHBOARD_CONTAINER"
docker rm "$DASHBOARD_CONTAINER"

# Create new dashboard with fixed environment
docker run -d \
    --name dashboard-fixed-v3 \
    --network "$CLOUDFLARED_NETWORK" \
    -e NODE_ENV=production \
    -e NEXTAUTH_URL=https://communication-dashboard.caramelme.com \
    -e NEXTAUTH_SECRET=your-nextauth-secret-here \
    -e API_BASE_URL=http://${API_IP}:3001 \
    -e DATABASE_URL=postgresql://dittofeed:dittofeed@postgres:5432/dittofeed \
    -e AUTH_MODE=multi-tenant \
    -e MULTITENANCY_ENABLED=true \
    -e ENABLE_WORKSPACE_QUOTA=true \
    -e NEXT_PUBLIC_API_BASE_URL=https://communication-api.caramelme.com \
    -e NEXT_PUBLIC_AUTH_MODE=multi-tenant \
    -e GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-your-google-client-id}" \
    -e GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-your-google-secret}" \
    "$DASHBOARD_IMAGE"

# Wait for container to start
sleep 5

# Get new dashboard IP
NEW_DASHBOARD_IP=$(docker inspect dashboard-fixed-v3 -f "{{.NetworkSettings.Networks.$CLOUDFLARED_NETWORK.IPAddress}}")
echo -e "${GREEN}New dashboard IP: $NEW_DASHBOARD_IP${NC}"

# Update Cloudflare config
cat > /tmp/cloudflare-config.yml <<EOF
tunnel: dittofeed-tunnel
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: communication-api.caramelme.com
    service: http://${API_IP}:3001
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      
  - hostname: communication-dashboard.caramelme.com  
    service: http://${NEW_DASHBOARD_IP}:3000
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      
  - service: http_status:404
EOF

# Restart cloudflared
CLOUDFLARED_CONTAINER=$(docker ps | grep cloudflared | head -1 | awk '{print $1}')
docker restart "$CLOUDFLARED_CONTAINER"

echo -e "\n${BLUE}Step 5: Checking new dashboard logs...${NC}"
sleep 5
docker logs dashboard-fixed-v3 --tail 20

echo -e "\n${GREEN}===================================================${NC}"
echo -e "${GREEN}Dashboard recreated with proper configuration${NC}"
echo -e "${GREEN}===================================================${NC}"
echo ""
echo "New dashboard IP: $NEW_DASHBOARD_IP"
echo "API endpoint: http://$API_IP:3001"
echo ""
echo -e "${YELLOW}Note: You need to set proper Google OAuth credentials:${NC}"
echo "  GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET"
echo ""
echo "Test after 30 seconds:"
echo "  curl -I https://communication-dashboard.caramelme.com/"