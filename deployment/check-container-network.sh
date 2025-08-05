#!/bin/bash
# Check container networking for Cloudflare tunnel

echo "=== Checking Container Networking ==="
echo ""

# Find container IDs
CLOUDFLARED_ID=$(docker ps -q -f name=cloudflared | head -1)
API_ID=$(docker ps -q -f name=api | head -1)
DASHBOARD_ID=$(docker ps -q -f name=dashboard | head -1)

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
echo "  Cloudflared:"
docker inspect $CLOUDFLARED_ID | grep -A 10 '"Networks"' | grep -E '"Name"|"IPAddress"' | head -4
echo ""
echo "  API:"
docker inspect $API_ID | grep -A 10 '"Networks"' | grep -E '"Name"|"IPAddress"' | head -4
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
    API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_ID)
    echo "    API container IP: $API_IP"
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
    DASH_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_ID)
    echo "    Dashboard container IP: $DASH_IP"
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