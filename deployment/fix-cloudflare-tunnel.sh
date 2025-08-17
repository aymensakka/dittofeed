#!/bin/bash

# ==============================================================================
# Fix Cloudflare Tunnel After Coolify Deployment
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
REMOTE_HOST="${1:-}"
REMOTE_USER="${2:-root}"

if [ -z "$REMOTE_HOST" ]; then
    print_error "Usage: $0 <coolify-server-ip> [username]"
    echo "Example: $0 192.168.1.100 root"
    exit 1
fi

print_header "Cloudflare Tunnel Fix for Dittofeed"

# Create remote script
cat <<'REMOTE_SCRIPT' | ssh "$REMOTE_USER@$REMOTE_HOST" "cat > /tmp/fix-tunnel.sh && chmod +x /tmp/fix-tunnel.sh"
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Finding Dittofeed containers...${NC}"

# Find containers
API_CONTAINER=$(docker ps | grep "api-" | head -1 | awk '{print $1}')
DASHBOARD_CONTAINER=$(docker ps | grep "dashboard-" | head -1 | awk '{print $1}')
CLOUDFLARED_CONTAINER=$(docker ps | grep cloudflared | head -1 | awk '{print $1}')

if [ -z "$API_CONTAINER" ]; then
    echo -e "${RED}API container not found${NC}"
    exit 1
fi

if [ -z "$DASHBOARD_CONTAINER" ]; then
    echo -e "${RED}Dashboard container not found${NC}"
    exit 1
fi

echo -e "${GREEN}Found API: $API_CONTAINER${NC}"
echo -e "${GREEN}Found Dashboard: $DASHBOARD_CONTAINER${NC}"

# Get container IPs
API_IP=$(docker inspect "$API_CONTAINER" -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)
DASHBOARD_IP=$(docker inspect "$DASHBOARD_CONTAINER" -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)

echo -e "${BLUE}Container IPs:${NC}"
echo -e "  API: $API_IP:3001"
echo -e "  Dashboard: $DASHBOARD_IP:3000"

# Check if containers are healthy
echo -e "\n${BLUE}Checking container health...${NC}"

# Check API
API_HEALTH=$(docker inspect "$API_CONTAINER" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
echo -e "API health: $API_HEALTH"

# Test API directly
if curl -sf "http://$API_IP:3001/api" > /dev/null 2>&1; then
    echo -e "${GREEN}API is responding${NC}"
else
    echo -e "${RED}API is not responding${NC}"
    
    # Check logs
    echo -e "\n${YELLOW}API logs:${NC}"
    docker logs "$API_CONTAINER" --tail 20
fi

# Test Dashboard directly
if curl -sf "http://$DASHBOARD_IP:3000" > /dev/null 2>&1; then
    echo -e "${GREEN}Dashboard is responding${NC}"
else
    echo -e "${RED}Dashboard is not responding${NC}"
    
    # Check logs
    echo -e "\n${YELLOW}Dashboard logs:${NC}"
    docker logs "$DASHBOARD_CONTAINER" --tail 20
fi

# Update Cloudflare tunnel configuration
if [ -n "$CLOUDFLARED_CONTAINER" ]; then
    echo -e "\n${BLUE}Cloudflare tunnel container found${NC}"
    
    # Check tunnel status
    docker logs "$CLOUDFLARED_CONTAINER" --tail 10
    
    echo -e "\n${YELLOW}To update tunnel routes:${NC}"
    echo "1. Update config.yml with new IPs:"
    echo "   - API: http://$API_IP:3001"
    echo "   - Dashboard: http://$DASHBOARD_IP:3000"
    echo "2. Restart cloudflared container"
else
    echo -e "\n${YELLOW}Cloudflare tunnel not found in containers${NC}"
    echo "You may need to update the tunnel configuration manually"
fi

# Check database
POSTGRES_CONTAINER=$(docker ps | grep postgres | grep -v supabase | head -1 | awk '{print $1}')
if [ -n "$POSTGRES_CONTAINER" ]; then
    TABLE_COUNT=$(docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d dittofeed -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
    echo -e "\n${BLUE}Database status:${NC} $TABLE_COUNT tables"
    
    if [ "$TABLE_COUNT" -eq "0" ]; then
        echo -e "${RED}Database not initialized!${NC}"
        echo "Run the database initialization fix first"
    fi
fi

echo -e "\n${BLUE}Summary:${NC}"
echo "API URL: http://$API_IP:3001"
echo "Dashboard URL: http://$DASHBOARD_IP:3000"
echo ""
echo "Update your Cloudflare tunnel configuration with these IPs"
echo "or update your DNS/proxy settings accordingly"
REMOTE_SCRIPT

print_info "Running diagnostics on server..."
ssh "$REMOTE_USER@$REMOTE_HOST" "/tmp/fix-tunnel.sh"

# Cleanup
ssh "$REMOTE_USER@$REMOTE_HOST" "rm -f /tmp/fix-tunnel.sh"

print_header "Next Steps"
echo "1. Update Cloudflare tunnel configuration with the new container IPs"
echo "2. Restart the cloudflared container if using Docker"
echo "3. Or update Cloudflare Zero Trust dashboard with new routes"
echo "4. Ensure the database is initialized (run fix-coolify-deployment.sh if needed)"