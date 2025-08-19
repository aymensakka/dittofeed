#!/bin/bash

# ==============================================================================
# Update Cloudflare Tunnel After Container Restart
# This script gets the new container IPs and shows how to update Cloudflare
# ==============================================================================

set -e

echo "====================================================="
echo "Cloudflare Tunnel Update After Restart"
echo "====================================================="
echo ""

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Find containers
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
CLOUDFLARED_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "cloudflared.*${PROJECT_ID}" | head -1)

echo "Step 1: Finding containers..."
echo "----------------------------------------"
echo "API: ${API_CONTAINER:-NOT FOUND}"
echo "Dashboard: ${DASHBOARD_CONTAINER:-NOT FOUND}"
echo "Cloudflared: ${CLOUDFLARED_CONTAINER:-NOT FOUND}"
echo ""

# Get current IPs
echo "Step 2: Getting current container IPs..."
echo "----------------------------------------"

if [ ! -z "$API_CONTAINER" ]; then
    API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER 2>/dev/null | head -c -1)
    echo "API IP: ${API_IP}:3001"
else
    echo "API container not found!"
fi

if [ ! -z "$DASHBOARD_CONTAINER" ]; then
    DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER 2>/dev/null | head -c -1)
    echo "Dashboard IP: ${DASHBOARD_IP}:3000"
else
    echo "Dashboard container not found!"
fi
echo ""

# Check current tunnel configuration
echo "Step 3: Current Cloudflare tunnel configuration..."
echo "----------------------------------------"

if [ ! -z "$CLOUDFLARED_CONTAINER" ]; then
    echo "Cloudflared container is running"
    echo "Checking tunnel config..."
    
    # Try to get the config from the container
    docker exec $CLOUDFLARED_CONTAINER cat /etc/cloudflared/config.yml 2>/dev/null || {
        echo "Could not read config from container"
        echo ""
        echo "Checking environment variables..."
        docker exec $CLOUDFLARED_CONTAINER env | grep -E "TUNNEL|URL" 2>/dev/null || echo "No tunnel env vars found"
    }
else
    echo "Cloudflared container not found!"
fi
echo ""

# Generate new configuration
echo "Step 4: New Cloudflare tunnel configuration needed..."
echo "====================================================="
echo ""
echo "UPDATE CLOUDFLARE ZERO TRUST DASHBOARD:"
echo "----------------------------------------"
echo "1. Go to: https://one.dash.cloudflare.com/"
echo "2. Navigate to: Access > Tunnels"
echo "3. Find your tunnel and click 'Configure'"
echo "4. Update the public hostname routes:"
echo ""
echo "   communication-api.caramelme.com"
echo "   Type: HTTP"
echo "   URL: http://${API_IP}:3001"
echo ""
echo "   communication-dashboard.caramelme.com"
echo "   Type: HTTP"
echo "   URL: http://${DASHBOARD_IP}:3000"
echo ""
echo "5. Save the configuration"
echo ""

# Alternative: Update via config file
echo "ALTERNATIVE: Update via config.yml"
echo "----------------------------------------"
cat > /tmp/cloudflared-config.yml << EOF
tunnel: $(docker exec $CLOUDFLARED_CONTAINER env | grep TUNNEL_ID | cut -d= -f2 2>/dev/null || echo "YOUR_TUNNEL_ID")
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: communication-api.caramelme.com
    service: http://${API_IP}:3001
    originRequest:
      noTLSVerify: true
      
  - hostname: communication-dashboard.caramelme.com
    service: http://${DASHBOARD_IP}:3000
    originRequest:
      noTLSVerify: true
      
  - service: http_status:404
EOF

echo "Config file generated at: /tmp/cloudflared-config.yml"
echo ""
echo "To apply this config:"
echo "1. Copy the config to the cloudflared container:"
echo "   docker cp /tmp/cloudflared-config.yml ${CLOUDFLARED_CONTAINER}:/etc/cloudflared/config.yml"
echo "2. Restart cloudflared:"
echo "   docker restart ${CLOUDFLARED_CONTAINER}"
echo ""

# Test connectivity
echo "Step 5: Testing connectivity..."
echo "----------------------------------------"

# Test if API is accessible
if [ ! -z "$API_IP" ]; then
    echo -n "Testing API connectivity: "
    docker run --rm --network ${PROJECT_ID} alpine/curl -s -o /dev/null -w "%{http_code}" http://${API_IP}:3001/health 2>/dev/null || echo "Failed to test"
fi

# Test if Dashboard is accessible
if [ ! -z "$DASHBOARD_IP" ]; then
    echo -n "Testing Dashboard connectivity: "
    docker run --rm --network ${PROJECT_ID} alpine/curl -s -o /dev/null -w "%{http_code}" http://${DASHBOARD_IP}:3000 2>/dev/null || echo "Failed to test"
fi
echo ""

# Summary
echo "====================================================="
echo "SUMMARY"
echo "====================================================="
echo "Container IPs that need to be updated in Cloudflare:"
echo "  API: http://${API_IP}:3001"
echo "  Dashboard: http://${DASHBOARD_IP}:3000"
echo ""
echo "After updating Cloudflare tunnel configuration,"
echo "wait 30-60 seconds for changes to propagate."
echo ""
echo "Then test:"
echo "  https://communication-api.caramelme.com"
echo "  https://communication-dashboard.caramelme.com"