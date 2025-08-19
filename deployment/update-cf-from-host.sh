#!/bin/bash

# This script runs on the HOST to update cloudflared config

CLOUDFLARED=$(docker ps --format '{{.Names}}' | grep -i cloudflared | head -1)

if [ -z "$CLOUDFLARED" ]; then
    echo "No cloudflared container found"
    exit 1
fi

# Get current IPs from other containers
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*p0gcsc088cogco0cokco4404" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*p0gcsc088cogco0cokco4404" | head -1)

API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER 2>/dev/null | head -c -1)
DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER 2>/dev/null | head -c -1)

# Use service names if IPs not found
[ -z "$API_IP" ] && API_IP="api"
[ -z "$DASHBOARD_IP" ] && DASHBOARD_IP="dashboard"

echo "Updating Cloudflare config with:"
echo "  API: $API_IP"
echo "  Dashboard: $DASHBOARD_IP"

# Create config on host
cat > /tmp/cloudflared-config.yml << EOF
tunnel: auto
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

# Copy to container
docker cp /tmp/cloudflared-config.yml ${CLOUDFLARED}:/etc/cloudflared/config.yml

# Restart cloudflared to apply changes
docker restart ${CLOUDFLARED}

echo "Cloudflare tunnel updated and restarted"