#!/bin/bash
# Setup Cloudflare Tunnel routes for locally managed tunnel
# Run this where you have cloudflared CLI and tunnel access

echo "Setting up Cloudflare Tunnel routes..."

# Configure ingress rules for the tunnel
cat > ~/.cloudflared/config.yml << EOF
tunnel: dittofeed-coolify
credentials-file: ~/.cloudflared/dittofeed-coolify.json

ingress:
  - hostname: api.com.caramelme.com
    service: http://localhost:3001
  - hostname: dashboard.com.caramelme.com  
    service: http://localhost:3000
  - hostname: grafana.com.caramelme.com
    service: http://localhost:3003
  - service: http_status:404
EOF

# Update DNS records
cloudflared tunnel route dns dittofeed-coolify api.com.caramelme.com
cloudflared tunnel route dns dittofeed-coolify dashboard.com.caramelme.com
cloudflared tunnel route dns dittofeed-coolify grafana.com.caramelme.com

echo "Routes configured. Start the tunnel with:"
echo "cloudflared tunnel run dittofeed-coolify"