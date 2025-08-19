#!/bin/bash

# Debug script to check cloudflared container setup

echo "====================================================="
echo "Debugging Cloudflared Container"
echo "====================================================="

# Find cloudflared container
CLOUDFLARED=$(docker ps --format '{{.Names}}' | grep -i cloudflared | head -1)

if [ -z "$CLOUDFLARED" ]; then
    echo "❌ No cloudflared container found"
    echo "Looking for any tunnel-related containers:"
    docker ps --format '{{.Names}}' | grep -E "tunnel|cloudflare|cf"
    exit 1
fi

echo "✅ Found cloudflared container: $CLOUDFLARED"
echo ""

# Check what shells are available
echo "Available shells in container:"
docker exec $CLOUDFLARED which sh 2>/dev/null && echo "  ✅ sh found" || echo "  ❌ sh not found"
docker exec $CLOUDFLARED which bash 2>/dev/null && echo "  ✅ bash found" || echo "  ❌ bash not found"
docker exec $CLOUDFLARED which ash 2>/dev/null && echo "  ✅ ash found" || echo "  ❌ ash not found"
echo ""

# Check if config directory exists
echo "Checking /etc/cloudflared directory:"
docker exec $CLOUDFLARED ls -la /etc/cloudflared/ 2>/dev/null || echo "  ❌ Directory not found or not accessible"
echo ""

# Check current config
echo "Current config.yml content:"
docker exec $CLOUDFLARED cat /etc/cloudflared/config.yml 2>/dev/null || echo "  ❌ No config.yml found"
echo ""

# Test if we can write to the config
echo "Testing write permissions:"
docker exec $CLOUDFLARED sh -c 'echo "# test" > /tmp/test.txt && echo "  ✅ Can write to /tmp" || echo "  ❌ Cannot write to /tmp"' 2>/dev/null
docker exec $CLOUDFLARED sh -c 'touch /etc/cloudflared/test.txt 2>/dev/null && rm /etc/cloudflared/test.txt && echo "  ✅ Can write to /etc/cloudflared" || echo "  ❌ Cannot write to /etc/cloudflared"'
echo ""

# Check how cloudflared is running
echo "Cloudflared process:"
docker exec $CLOUDFLARED ps aux | grep cloudflared | grep -v grep || echo "  Process not found with ps aux"
echo ""

# Check environment variables
echo "Relevant environment variables:"
docker exec $CLOUDFLARED env | grep -E "TUNNEL|CF_|DOMAIN" | head -10
echo ""

# Try to create and execute a simple script
echo "Testing script creation and execution:"
docker exec $CLOUDFLARED sh -c 'echo "echo hello" > /test.sh && chmod +x /test.sh && /test.sh && rm /test.sh && echo "  ✅ Script execution works" || echo "  ❌ Script execution failed"' 2>&1
echo ""

# Check if cat command exists
echo "Checking for cat command:"
docker exec $CLOUDFLARED which cat 2>/dev/null && echo "  ✅ cat found" || echo "  ❌ cat not found"
echo ""

# Try the actual update command
echo "Testing the actual update command:"
docker exec $CLOUDFLARED sh -c 'cat>/tmp/test-config.yml<<E
tunnel: auto
credentials-file: /etc/cloudflared/credentials.json

ingress:
- hostname: communication-api.caramelme.com
  service: http://api:3001
- hostname: communication-dashboard.caramelme.com
  service: http://dashboard:3000
- service: http_status:404
E' 2>&1

if [ $? -eq 0 ]; then
    echo "  ✅ Heredoc syntax works"
    echo "  Test config created:"
    docker exec $CLOUDFLARED cat /tmp/test-config.yml 2>/dev/null
else
    echo "  ❌ Heredoc syntax failed"
fi
echo ""

echo "====================================================="
echo "Debug complete"
echo "====================================================="
