#!/bin/bash

# ==============================================================================
# Update Cloudflare Tunnel Configuration with Container IPs
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Configuration
REMOTE_HOST="${1:-91.107.214.94}"
REMOTE_USER="${2:-root}"

if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [coolify-server-ip] [username]"
    echo "Example: $0 91.107.214.94 root"
    exit 0
fi

print_header "Cloudflare Tunnel Update for Dittofeed"

# Create and execute remote script
cat <<'REMOTE_SCRIPT' | ssh "$REMOTE_USER@$REMOTE_HOST" "cat > /tmp/update-tunnel.sh && chmod +x /tmp/update-tunnel.sh && bash /tmp/update-tunnel.sh"
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Step 1: Finding containers...${NC}"

# Find cloudflared container and network
CLOUDFLARED_CONTAINER=$(docker ps | grep cloudflared | head -1 | awk '{print $1}')
if [ -z "$CLOUDFLARED_CONTAINER" ]; then
    echo -e "${RED}Cloudflared container not found${NC}"
    exit 1
fi

# Get cloudflared network
CLOUDFLARED_NETWORK=$(docker inspect "$CLOUDFLARED_CONTAINER" --format='{{range $key, $value := .NetworkSettings.Networks}}{{$key}}{{end}}' | head -1)
echo -e "${GREEN}Cloudflared network: $CLOUDFLARED_NETWORK${NC}"

# Find and connect dashboard
DASHBOARD_CONTAINER=$(docker ps | grep -E "(dashboard-fixed|dashboard-)" | head -1 | awk '{print $1}')
if [ -n "$DASHBOARD_CONTAINER" ]; then
    echo -e "${BLUE}Connecting dashboard to cloudflared network...${NC}"
    docker network connect "$CLOUDFLARED_NETWORK" "$DASHBOARD_CONTAINER" 2>/dev/null || true
    DASHBOARD_IP=$(docker inspect "$DASHBOARD_CONTAINER" -f "{{.NetworkSettings.Networks.$CLOUDFLARED_NETWORK.IPAddress}}")
    echo -e "${GREEN}Dashboard IP: $DASHBOARD_IP${NC}"
fi

# Find and connect API
API_CONTAINER=$(docker ps | grep "api-" | head -1 | awk '{print $1}')
if [ -n "$API_CONTAINER" ]; then
    echo -e "${BLUE}Connecting API to cloudflared network...${NC}"
    docker network connect "$CLOUDFLARED_NETWORK" "$API_CONTAINER" 2>/dev/null || true
    API_IP=$(docker inspect "$API_CONTAINER" -f "{{.NetworkSettings.Networks.$CLOUDFLARED_NETWORK.IPAddress}}")
    echo -e "${GREEN}API IP: $API_IP${NC}"
fi

echo -e "\n${BLUE}Step 2: Creating updated Cloudflare config...${NC}"

# Create config.yml for cloudflared
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

echo -e "${GREEN}Config created${NC}"

# Check if cloudflared container has a volume mount for config
VOLUME_MOUNT=$(docker inspect "$CLOUDFLARED_CONTAINER" --format='{{range .Mounts}}{{if eq .Destination "/etc/cloudflared"}}{{.Source}}{{end}}{{end}}')

if [ -n "$VOLUME_MOUNT" ]; then
    echo -e "${BLUE}Updating config at volume mount: $VOLUME_MOUNT${NC}"
    cp /tmp/cloudflare-config.yml "$VOLUME_MOUNT/config.yml" 2>/dev/null || {
        echo -e "${YELLOW}Could not update volume config, will restart with new config${NC}"
    }
fi

echo -e "\n${BLUE}Step 3: Restarting cloudflared with updated config...${NC}"

# Restart cloudflared
docker restart "$CLOUDFLARED_CONTAINER"

# Wait for it to come up
sleep 5

# Check logs
echo -e "\n${BLUE}Cloudflared logs:${NC}"
docker logs "$CLOUDFLARED_CONTAINER" --tail 10

echo -e "\n${GREEN}===== Update Complete =====${NC}"
echo "Dashboard URL: https://communication-dashboard.caramelme.com"
echo "API URL: https://communication-api.caramelme.com"
echo ""
echo "Test with:"
echo "  curl -I https://communication-dashboard.caramelme.com/"
echo "  curl https://communication-api.caramelme.com/api"

# Test connectivity
echo -e "\n${BLUE}Testing connectivity...${NC}"
if [ -n "$DASHBOARD_IP" ]; then
    if curl -sf "http://$DASHBOARD_IP:3000" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Dashboard is responding internally${NC}"
    else
        echo -e "${RED}✗ Dashboard not responding internally${NC}"
    fi
fi

if [ -n "$API_IP" ]; then
    if curl -sf "http://$API_IP:3001/api" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ API is responding internally${NC}"
    else
        echo -e "${RED}✗ API not responding internally${NC}"
    fi
fi
REMOTE_SCRIPT

# Cleanup
ssh "$REMOTE_USER@$REMOTE_HOST" "rm -f /tmp/update-tunnel.sh"

print_header "Next Steps"
echo "1. Wait 30 seconds for Cloudflare tunnel to reconnect"
echo "2. Test the URLs:"
echo "   curl -I https://communication-dashboard.caramelme.com/"
echo "   curl https://communication-api.caramelme.com/api"
echo ""
echo "If still getting 502 errors:"
echo "  - Check Cloudflare Zero Trust dashboard"
echo "  - Verify tunnel is connected"
echo "  - Check DNS records point to tunnel"