#!/bin/bash
# Check container networking for Cloudflare tunnel

echo "=== Checking Container Networking ==="
echo ""

# Find container IDs - Coolify uses unique naming
CLOUDFLARED_ID=$(docker ps -q -f name=cloudflared | head -1)
API_ID=$(docker ps | grep -E "api-[a-z0-9]+" | grep -v grep | awk '{print $1}' | head -1)
DASHBOARD_ID=$(docker ps | grep -E "dashboard-[a-z0-9]+" | grep -v grep | awk '{print $1}' | head -1)

# Show all running containers for debugging
echo "All running containers:"
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" | head -10
echo ""

if [ -z "$CLOUDFLARED_ID" ]; then
    echo "❌ Cloudflared container not found"
    exit 1
fi

echo "Container IDs:"
echo "  Cloudflared: $CLOUDFLARED_ID"
echo "  API: $API_ID"
echo "  Dashboard: $DASHBOARD_ID"
echo ""

# Check networks
echo "Networks:"
if [ -n "$CLOUDFLARED_ID" ]; then
    echo "  Cloudflared:"
    docker inspect $CLOUDFLARED_ID | grep -A 10 '"Networks"' | grep -E '"Name"|"IPAddress"' | head -4
fi
echo ""
if [ -n "$API_ID" ]; then
    echo "  API:"
    docker inspect $API_ID | grep -A 10 '"Networks"' | grep -E '"Name"|"IPAddress"' | head -4
else
    echo "  API: Container not found"
fi
echo ""
if [ -n "$DASHBOARD_ID" ]; then
    echo "  Dashboard:"
    docker inspect $DASHBOARD_ID | grep -A 10 '"Networks"' | grep -E '"Name"|"IPAddress"' | head -4
else
    echo "  Dashboard: Container not found"
fi
echo ""

# Test connectivity from cloudflared
echo "Testing connectivity from cloudflared container:"
echo ""

echo -n "  Can reach api:3001: "
if docker exec $CLOUDFLARED_ID wget -q -O- http://api:3001/health > /dev/null 2>&1; then
    echo "✅ YES"
else
    echo "❌ NO"
    # Try with IP
    if [ -n "$API_ID" ]; then
        API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_ID)
        echo "    API container IP: $API_IP"
    else
        echo "    API container not found"
    fi
    echo -n "    Can reach $API_IP:3001: "
    if docker exec $CLOUDFLARED_ID wget -q -O- http://$API_IP:3001/health > /dev/null 2>&1; then
        echo "✅ YES - Use http://$API_IP:3001 in Cloudflare"
    else
        echo "❌ NO"
    fi
fi

echo -n "  Can reach dashboard:3000: "
if docker exec $CLOUDFLARED_ID wget -q -O- http://dashboard:3000 > /dev/null 2>&1; then
    echo "✅ YES"
else
    echo "❌ NO"
    # Try with IP
    if [ -n "$DASHBOARD_ID" ]; then
        DASH_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_ID)
        echo "    Dashboard container IP: $DASH_IP"
    else
        echo "    Dashboard container not found"
    fi
    echo -n "    Can reach $DASH_IP:3000: "
    if docker exec $CLOUDFLARED_ID wget -q -O- http://$DASH_IP:3000 > /dev/null 2>&1; then
        echo "✅ YES - Use http://$DASH_IP:3000 in Cloudflare"
    else
        echo "❌ NO"
    fi
fi

echo ""
echo "=== Recommendations ==="
echo "In Cloudflare tunnel configuration, use the working URLs shown above."