#!/bin/bash

# ==============================================================================
# Scheduled Task 2: Dashboard IP + Cloudflare Update (Runs in Dashboard container)
# 
# Coolify Scheduled Task:
# Name: Dashboard Cloudflare Updater
# Container: dashboard
# Command: bash /service/deployment/cron-dashboard-update-cloudflare.sh
# Frequency: */5 * * * * (every 5 minutes, offset by 1 minute)
# ==============================================================================

echo "[$(date)] Dashboard container updating Cloudflare..."

# Get Dashboard container IP
DASHBOARD_IP=$(hostname -i 2>/dev/null || ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -1)
DASHBOARD_HOSTNAME=$(hostname)

# Get workspace info from environment
WORKSPACE_DOMAIN="${DOMAIN:-caramelme.com}"

# Get API IP via DNS resolution (docker-compose service discovery)
API_IP=""

# Try different methods to get API IP
if command -v nslookup > /dev/null 2>&1; then
    API_IP=$(nslookup api 2>/dev/null | grep Address | tail -1 | awk '{print $2}' | grep -v '#')
fi

if [ -z "$API_IP" ] && command -v getent > /dev/null 2>&1; then
    API_IP=$(getent hosts api 2>/dev/null | awk '{print $1}')
fi

if [ -z "$API_IP" ]; then
    API_IP=$(ping -c 1 api 2>/dev/null | grep PING | sed -e "s/.*(\(.*\)).*/\1/" || true)
fi

# Default to service name if IP not found
if [ -z "$API_IP" ]; then
    API_IP="api"
    echo "[$(date)] Warning: Could not resolve API IP, using service name"
fi

echo "[$(date)] IPs - API: ${API_IP}, Dashboard: ${DASHBOARD_IP}"

# Create Cloudflare config
cat > /tmp/cloudflared-config.yml << EOF
tunnel: auto
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: communication-api.${WORKSPACE_DOMAIN}
    service: http://${API_IP}:3001
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      
  - hostname: communication-dashboard.${WORKSPACE_DOMAIN}
    service: http://${DASHBOARD_IP}:3000
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      
  - service: http_status:404
EOF

# Check if IPs have changed by comparing with last known state
STATE_FILE="/tmp/cloudflare-ips-state.txt"
CURRENT_STATE="${API_IP}:${DASHBOARD_IP}"

UPDATE_NEEDED=false
if [ -f "$STATE_FILE" ]; then
    PREVIOUS_STATE=$(cat "$STATE_FILE")
    if [ "$CURRENT_STATE" != "$PREVIOUS_STATE" ]; then
        UPDATE_NEEDED=true
        echo "[$(date)] IP change detected"
    fi
else
    UPDATE_NEEDED=true
    echo "[$(date)] First run, update needed"
fi

if [ "$UPDATE_NEEDED" = true ]; then
    echo "[$(date)] Updating Cloudflare tunnel configuration..."
    
    # Try to connect to cloudflared container via network
    # In docker-compose, we can try to communicate with cloudflared service
    
    # Method 1: Try to copy file to a shared volume if it exists
    if [ -d "/shared" ]; then
        cp /tmp/cloudflared-config.yml /shared/cloudflared-config.yml 2>/dev/null && \
        echo "[$(date)] Config copied to shared volume"
    fi
    
    # Method 2: Try to send config via network call to cloudflared
    # This would require cloudflared to have an API endpoint for config updates
    
    # Method 3: Write instructions for manual update
    cat > /tmp/cloudflare-update-instructions.txt << INSTRUCTIONS
=========================================================
CLOUDFLARE TUNNEL UPDATE REQUIRED
=========================================================
IPs have changed. To update Cloudflare tunnel:

1. From the HOST machine, run:
   
   # Get the config from dashboard container
   docker cp ${DASHBOARD_HOSTNAME}:/tmp/cloudflared-config.yml /tmp/cf-config.yml
   
   # Find cloudflared container
   CLOUDFLARED=\$(docker ps --format '{{.Names}}' | grep cloudflared | head -1)
   
   # Update cloudflared
   docker cp /tmp/cf-config.yml \$CLOUDFLARED:/etc/cloudflared/config.yml
   docker restart \$CLOUDFLARED

2. Or update in Cloudflare Zero Trust Dashboard:
   
   communication-api.${WORKSPACE_DOMAIN} → http://${API_IP}:3001
   communication-dashboard.${WORKSPACE_DOMAIN} → http://${DASHBOARD_IP}:3000

Current IPs:
  API: ${API_IP}
  Dashboard: ${DASHBOARD_IP}
=========================================================
INSTRUCTIONS
    
    # Save current state
    echo "$CURRENT_STATE" > "$STATE_FILE"
    
    # Log the update
    echo "[$(date)] Cloudflare config prepared. Manual update may be required."
    echo "[$(date)] Instructions written to /tmp/cloudflare-update-instructions.txt"
    
    # Create a webhook notification file that external monitor can detect
    cat > /tmp/cloudflare-update-webhook.json << WEBHOOK
{
  "timestamp": "$(date -Iseconds)",
  "event": "ip_change",
  "api_ip": "${API_IP}",
  "dashboard_ip": "${DASHBOARD_IP}",
  "config_file": "/tmp/cloudflared-config.yml",
  "action_required": "update_cloudflare"
}
WEBHOOK
    
else
    echo "[$(date)] No IP changes detected, skipping update"
fi

# Write current status
cat > /tmp/dashboard-status.json << EOF
{
  "timestamp": "$(date -Iseconds)",
  "dashboard_ip": "${DASHBOARD_IP}",
  "dashboard_hostname": "${DASHBOARD_HOSTNAME}",
  "api_ip": "${API_IP}",
  "workspace_domain": "${WORKSPACE_DOMAIN}",
  "last_check": "$(date)",
  "update_performed": ${UPDATE_NEEDED}
}
EOF

echo "[$(date)] Dashboard Cloudflare check complete"

exit 0