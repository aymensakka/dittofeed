#!/bin/bash

# ==============================================================================
# Scheduled Task 1: API IP Collector (Runs in API container)
# 
# Coolify Scheduled Task:
# Name: API IP Collector
# Container: api
# Command: bash /service/deployment/cron-api-ip.sh
# Frequency: */5 * * * * (every 5 minutes)
# ==============================================================================

echo "[$(date)] API container collecting IP..."

# Get API container IP
API_IP=$(hostname -i 2>/dev/null || ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -1)
API_HOSTNAME=$(hostname)

# Get workspace info from environment
WORKSPACE_DOMAIN="${DOMAIN:-caramelme.com}"

# Write API IP to a file
cat > /tmp/api-ip.json << EOF
{
  "timestamp": "$(date -Iseconds)",
  "api_ip": "${API_IP}",
  "api_hostname": "${API_HOSTNAME}",
  "api_port": 3001,
  "workspace_domain": "${WORKSPACE_DOMAIN}"
}
EOF

echo "[$(date)] API IP collected: ${API_IP}"

# Also write to a simple text file for easier parsing
echo "${API_IP}" > /tmp/api-ip.txt
echo "$(date -Iseconds):${API_IP}" >> /tmp/api-ip-history.log

exit 0