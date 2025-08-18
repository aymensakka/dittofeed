#!/bin/bash

# ==============================================================================
# Fix Cloudflare Tunnel - Direct Server Script
# Run this directly on the Coolify server
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}Fixing Cloudflare Tunnel Configuration${NC}"
echo -e "${BLUE}===================================================${NC}"

echo -e "\n${BLUE}Step 1: Finding containers...${NC}"

# Find cloudflared container and network
CLOUDFLARED_CONTAINER=$(docker ps | grep cloudflared | head -1 | awk '{print $1}')
if [ -z "$CLOUDFLARED_CONTAINER" ]; then
    echo -e "${RED}Cloudflared container not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Cloudflared container: $CLOUDFLARED_CONTAINER${NC}"

# Get cloudflared network
CLOUDFLARED_NETWORK=$(docker inspect "$CLOUDFLARED_CONTAINER" --format='{{range $key, $value := .NetworkSettings.Networks}}{{$key}}{{end}}' | head -1)
echo -e "${GREEN}✓ Cloudflared network: $CLOUDFLARED_NETWORK${NC}"

# Find and connect dashboard
DASHBOARD_CONTAINER=$(docker ps | grep -E "(dashboard-fixed|dashboard-)" | head -1 | awk '{print $1}')
if [ -n "$DASHBOARD_CONTAINER" ]; then
    echo -e "${BLUE}Connecting dashboard to cloudflared network...${NC}"
    docker network connect "$CLOUDFLARED_NETWORK" "$DASHBOARD_CONTAINER" 2>/dev/null || echo "Already connected"
    DASHBOARD_IP=$(docker inspect "$DASHBOARD_CONTAINER" -f "{{.NetworkSettings.Networks.$CLOUDFLARED_NETWORK.IPAddress}}")
    echo -e "${GREEN}✓ Dashboard IP on tunnel network: $DASHBOARD_IP${NC}"
else
    echo -e "${RED}Dashboard container not found${NC}"
fi

# Find and connect API
API_CONTAINER=$(docker ps | grep "api-" | head -1 | awk '{print $1}')
if [ -n "$API_CONTAINER" ]; then
    echo -e "${BLUE}Connecting API to cloudflared network...${NC}"
    docker network connect "$CLOUDFLARED_NETWORK" "$API_CONTAINER" 2>/dev/null || echo "Already connected"
    API_IP=$(docker inspect "$API_CONTAINER" -f "{{.NetworkSettings.Networks.$CLOUDFLARED_NETWORK.IPAddress}}")
    echo -e "${GREEN}✓ API IP on tunnel network: $API_IP${NC}"
else
    echo -e "${RED}API container not found${NC}"
fi

echo -e "\n${BLUE}Step 2: Testing internal connectivity...${NC}"

# Test dashboard
if [ -n "$DASHBOARD_IP" ]; then
    if curl -sf "http://$DASHBOARD_IP:3000" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Dashboard is responding at http://$DASHBOARD_IP:3000${NC}"
    else
        echo -e "${RED}✗ Dashboard not responding${NC}"
        echo -e "${YELLOW}Dashboard logs:${NC}"
        docker logs "$DASHBOARD_CONTAINER" --tail 5
    fi
fi

# Test API
if [ -n "$API_IP" ]; then
    if curl -sf "http://$API_IP:3001/api" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ API is responding at http://$API_IP:3001${NC}"
    else
        echo -e "${RED}✗ API not responding${NC}"
        echo -e "${YELLOW}API logs:${NC}"
        docker logs "$API_CONTAINER" --tail 5
    fi
fi

echo -e "\n${BLUE}Step 3: Creating Cloudflare tunnel config...${NC}"

# Create updated config
cat > /tmp/cloudflare-config.yml <<EOF
tunnel: dittofeed-tunnel
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: communication-api.caramelme.com
    service: http://${API_IP:-172.27.0.5}:3001
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      
  - hostname: communication-dashboard.caramelme.com  
    service: http://${DASHBOARD_IP:-172.27.0.6}:3000
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      
  - service: http_status:404
EOF

echo -e "${GREEN}✓ Config created${NC}"
cat /tmp/cloudflare-config.yml

echo -e "\n${BLUE}Step 4: Restarting cloudflared...${NC}"
docker restart "$CLOUDFLARED_CONTAINER"

# Wait for restart
sleep 5

# Check logs
echo -e "\n${BLUE}Cloudflared status:${NC}"
docker logs "$CLOUDFLARED_CONTAINER" --tail 10

echo -e "\n${GREEN}===================================================${NC}"
echo -e "${GREEN}Configuration Complete!${NC}"
echo -e "${GREEN}===================================================${NC}"
echo ""
echo "Dashboard: https://communication-dashboard.caramelme.com"
echo "API: https://communication-api.caramelme.com"
echo ""
echo -e "${YELLOW}Wait 30 seconds for tunnel to reconnect, then test:${NC}"
echo "  curl -I https://communication-dashboard.caramelme.com/"
echo "  curl https://communication-api.caramelme.com/api"