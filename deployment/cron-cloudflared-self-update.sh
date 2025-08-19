#!/bin/sh

# ==============================================================================
# Scheduled Task 3: Cloudflared Self-Update (Runs in Cloudflared container)
# 
# Coolify Scheduled Task:
# Name: Cloudflare Tunnel Self Update
# Container: cloudflared
# Command: sh /etc/cloudflared/cron-self-update.sh
# Frequency: */5 * * * * (every 5 minutes, offset by 2 minutes)
# ==============================================================================

echo "[$(date)] Cloudflared checking for IP updates..."

# Configuration
WORKSPACE_DOMAIN="${DOMAIN:-caramelme.com}"
CONFIG_FILE="/etc/cloudflared/config.yml"
STATE_FILE="/tmp/tunnel-ips-state.txt"

# Get current IPs via DNS resolution
API_IP=""
DASHBOARD_IP=""

# Try to resolve API IP
if command -v nslookup > /dev/null 2>&1; then
    API_IP=$(nslookup api 2>/dev/null | grep -A1 "Name:" | grep Address | awk '{print $2}')
fi

if [ -z "$API_IP" ] && command -v getent > /dev/null 2>&1; then
    API_IP=$(getent hosts api 2>/dev/null | awk '{print $1}')
fi

# Try to resolve Dashboard IP
if command -v nslookup > /dev/null 2>&1; then
    DASHBOARD_IP=$(nslookup dashboard 2>/dev/null | grep -A1 "Name:" | grep Address | awk '{print $2}')
fi

if [ -z "$DASHBOARD_IP" ] && command -v getent > /dev/null 2>&1; then
    DASHBOARD_IP=$(getent hosts dashboard 2>/dev/null | awk '{print $1}')
fi

# If we couldn't resolve, try using service names
if [ -z "$API_IP" ]; then
    API_IP="api"
    echo "[$(date)] Using service name for API"
fi

if [ -z "$DASHBOARD_IP" ]; then
    DASHBOARD_IP="dashboard"
    echo "[$(date)] Using service name for Dashboard"
fi

echo "[$(date)] Resolved IPs - API: ${API_IP}, Dashboard: ${DASHBOARD_IP}"

# Check if IPs have changed
CURRENT_STATE="${API_IP}:${DASHBOARD_IP}"
UPDATE_NEEDED=false

if [ -f "$STATE_FILE" ]; then
    PREVIOUS_STATE=$(cat "$STATE_FILE")
    if [ "$CURRENT_STATE" != "$PREVIOUS_STATE" ]; then
        UPDATE_NEEDED=true
        echo "[$(date)] IP change detected: ${PREVIOUS_STATE} -> ${CURRENT_STATE}"
    fi
else
    UPDATE_NEEDED=true
    echo "[$(date)] First run, creating config"
fi

if [ "$UPDATE_NEEDED" = "true" ]; then
    echo "[$(date)] Updating Cloudflare tunnel configuration..."
    
    # Backup existing config
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
    fi
    
    # Create new config
    cat > "$CONFIG_FILE" << EOF
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
    
    # Save new state
    echo "$CURRENT_STATE" > "$STATE_FILE"
    
    # The tunnel should automatically reload with the new config
    # If not, we can try to signal cloudflared to reload
    
    # Try to find cloudflared process and send HUP signal for reload
    CLOUDFLARED_PID=$(pgrep cloudflared)
    if [ ! -z "$CLOUDFLARED_PID" ]; then
        kill -HUP $CLOUDFLARED_PID 2>/dev/null && \
        echo "[$(date)] Sent reload signal to cloudflared" || \
        echo "[$(date)] Could not send reload signal"
    fi
    
    echo "[$(date)] Cloudflare tunnel configuration updated"
    
    # Log the update
    echo "[$(date)] Updated: API=${API_IP}:3001, Dashboard=${DASHBOARD_IP}:3000" >> /tmp/cloudflare-updates.log
else
    echo "[$(date)] No IP changes, config unchanged"
fi

echo "[$(date)] Cloudflared self-update check complete"

exit 0