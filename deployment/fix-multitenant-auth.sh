#!/bin/bash

# ==============================================================================
# Fix Multi-Tenant Auth Configuration
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}Fixing Multi-Tenant Auth Configuration${NC}"
echo -e "${BLUE}===================================================${NC}"

# Find containers
DASHBOARD_CONTAINER=$(docker ps | grep dashboard | grep -v fixed | head -1 | awk '{print $1}')
API_CONTAINER=$(docker ps | grep "api-" | head -1 | awk '{print $1}')
POSTGRES_CONTAINER=$(docker ps | grep postgres | grep -v supabase | head -1 | awk '{print $1}')

if [ -z "$DASHBOARD_CONTAINER" ]; then
    # Try to find any dashboard container
    DASHBOARD_CONTAINER=$(docker ps | grep dashboard | head -1 | awk '{print $1}')
fi

echo -e "\n${BLUE}Step 1: Current container status${NC}"
echo "Dashboard: $DASHBOARD_CONTAINER"
echo "API: $API_CONTAINER"
echo "PostgreSQL: $POSTGRES_CONTAINER"

# Get cloudflared network
CLOUDFLARED_CONTAINER=$(docker ps | grep cloudflared | head -1 | awk '{print $1}')
CLOUDFLARED_NETWORK=$(docker inspect "$CLOUDFLARED_CONTAINER" --format='{{range $key, $value := .NetworkSettings.Networks}}{{$key}}{{end}}' | head -1)

# Get API IP on cloudflared network
API_IP=$(docker inspect "$API_CONTAINER" -f "{{.NetworkSettings.Networks.$CLOUDFLARED_NETWORK.IPAddress}}")
echo -e "${GREEN}API IP on tunnel network: $API_IP${NC}"

# Get PostgreSQL connection details
POSTGRES_IP=$(docker inspect "$POSTGRES_CONTAINER" -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)
echo -e "${GREEN}PostgreSQL IP: $POSTGRES_IP${NC}"

echo -e "\n${BLUE}Step 2: Stopping current dashboard container${NC}"
docker stop "$DASHBOARD_CONTAINER" 2>/dev/null || true
docker rm "$DASHBOARD_CONTAINER" 2>/dev/null || true

echo -e "\n${BLUE}Step 3: Creating new dashboard with proper auth configuration${NC}"

# Create new dashboard with comprehensive multi-tenant configuration
docker run -d \
    --name dashboard-multitenant \
    --network "$CLOUDFLARED_NETWORK" \
    -e NODE_ENV=production \
    -e NEXTAUTH_URL=https://communication-dashboard.caramelme.com \
    -e NEXTAUTH_SECRET=m68OINfp4YRVtVds/oeMSxkQobxePK4lTPtq7hWcYdE= \
    -e API_BASE_URL=http://${API_IP}:3001 \
    -e DATABASE_URL=postgresql://dittofeed:LOpnL3wYIbWUBax4qXeR@${POSTGRES_IP}:5432/dittofeed \
    -e AUTH_MODE=multi-tenant \
    -e AUTH_PROVIDER=google \
    -e MULTITENANCY_ENABLED=true \
    -e ENABLE_WORKSPACE_QUOTA=true \
    -e NEXT_PUBLIC_API_BASE_URL=https://communication-api.caramelme.com \
    -e NEXT_PUBLIC_AUTH_MODE=multi-tenant \
    -e NEXT_PUBLIC_AUTH_PROVIDER=google \
    -e GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-your-google-client-id-here}" \
    -e GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-your-google-client-secret-here}" \
    -e GOOGLE_OAUTH_REDIRECT_URI=https://communication-dashboard.caramelme.com/api/auth/callback/google \
    -e ENABLE_GOOGLE_OAUTH=true \
    -e OAUTH_PROVIDERS=google \
    docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1

# Wait for container to start
sleep 5

# Get new dashboard IP
NEW_DASHBOARD_IP=$(docker inspect dashboard-multitenant -f "{{.NetworkSettings.Networks.$CLOUDFLARED_NETWORK.IPAddress}}")
echo -e "${GREEN}New dashboard IP: $NEW_DASHBOARD_IP${NC}"

echo -e "\n${BLUE}Step 4: Updating Cloudflare tunnel configuration${NC}"

# Create updated Cloudflare config
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
docker restart "$CLOUDFLARED_CONTAINER"

echo -e "\n${BLUE}Step 5: Checking dashboard logs${NC}"
sleep 5
docker logs dashboard-multitenant --tail 20

echo -e "\n${BLUE}Step 6: Testing connectivity${NC}"

# Test dashboard internally
if curl -sf "http://$NEW_DASHBOARD_IP:3000" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Dashboard is responding internally${NC}"
else
    echo -e "${RED}✗ Dashboard not responding internally${NC}"
fi

# Test API
if curl -sf "http://$API_IP:3001/api" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ API is responding${NC}"
else
    echo -e "${RED}✗ API not responding${NC}"
fi

echo -e "\n${GREEN}===================================================${NC}"
echo -e "${GREEN}Multi-Tenant Auth Configuration Complete${NC}"
echo -e "${GREEN}===================================================${NC}"
echo ""
echo "Dashboard: https://communication-dashboard.caramelme.com"
echo "API: https://communication-api.caramelme.com"
echo ""
echo -e "${YELLOW}Google OAuth Configuration:${NC}"
echo "  Client ID: ${GOOGLE_CLIENT_ID:-[Set GOOGLE_CLIENT_ID environment variable]}"
echo "  Redirect URI: https://communication-dashboard.caramelme.com/api/auth/callback/google"
echo ""
echo -e "${YELLOW}In Google Cloud Console, ensure:${NC}"
echo "  1. OAuth 2.0 Client ID is configured"
echo "  2. Authorized redirect URIs includes:"
echo "     https://communication-dashboard.caramelme.com/api/auth/callback/google"
echo "  3. Authorized JavaScript origins includes:"
echo "     https://communication-dashboard.caramelme.com"
echo ""
echo "Test the deployment:"
echo "  curl -I https://communication-dashboard.caramelme.com/"