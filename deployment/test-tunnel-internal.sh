#!/bin/bash
# Test Cloudflare tunnel from inside the server

echo "=== Testing Cloudflare Tunnel Configuration ==="
echo ""

# Check tunnel status
echo "1. Cloudflare Tunnel Status:"
echo "----------------------------"
CLOUDFLARED=$(docker ps -q -f name="cloudflared-p0gcsc088cogco0cokco4404" | head -1)
if [ -n "$CLOUDFLARED" ]; then
    echo "Tunnel container: Running"
    echo "Recent logs:"
    docker logs --tail 30 $CLOUDFLARED 2>&1 | grep -E "INF|ERR|error|failed|route|hostname"
else
    echo "❌ Cloudflared container not found!"
fi

echo ""
echo "2. Testing Internal Services:"
echo "-----------------------------"
# Test if services respond internally
API_CONTAINER=$(docker ps --format "{{.Names}}" | grep "api-p0gcsc088cogco0cokco4404" | head -1)
DASH_CONTAINER=$(docker ps --format "{{.Names}}" | grep "dashboard-p0gcsc088cogco0cokco4404" | head -1)

echo "API Container: $API_CONTAINER"
echo "Dashboard Container: $DASH_CONTAINER"

# Test direct container access
echo ""
echo "3. Direct Container Tests:"
echo "--------------------------"
if [ -n "$API_CONTAINER" ]; then
    echo -n "API direct test: "
    docker run --rm --network p0gcsc088cogco0cokco4404 curlimages/curl -s -o /dev/null -w "%{http_code}" http://${API_CONTAINER}:3001/health || echo "Failed"
fi

if [ -n "$DASH_CONTAINER" ]; then
    echo -n "Dashboard direct test: "
    docker run --rm --network p0gcsc088cogco0cokco4404 curlimages/curl -s -o /dev/null -w "%{http_code}" http://${DASH_CONTAINER}:3000 || echo "Failed"
fi

echo ""
echo "4. Cloudflare Dashboard Check:"
echo "------------------------------"
echo "Please verify in Cloudflare Zero Trust:"
echo "1. Go to: https://one.dash.cloudflare.com/"
echo "2. Navigate to: Networks → Tunnels"
echo "3. Check your tunnel status (should be ACTIVE/green)"
echo "4. Click on the tunnel name"
echo "5. Go to 'Public Hostname' tab"
echo "6. Verify routes are exactly:"
echo "   - api.com.caramelme.com → http://${API_CONTAINER}:3001"
echo "   - dashboard.com.caramelme.com → http://${DASH_CONTAINER}:3000"
echo ""
echo "7. Also check the 'Overview' tab to see if the tunnel is connected"
echo "8. Check if there are any error messages"

echo ""
echo "5. Alternative - Use Tunnel ID instead:"
echo "---------------------------------------"
echo "If container names don't work, try using localhost with different ports:"
echo "   - api.com.caramelme.com → http://localhost:3001"
echo "   - dashboard.com.caramelme.com → http://localhost:3000"
echo ""
echo "But this requires the cloudflared container to be in host network mode."