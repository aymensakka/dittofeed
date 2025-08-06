#!/bin/bash
# Check Cloudflare tunnel and service status

echo "=========================================="
echo "🔍 Checking Cloudflare Tunnel Status"
echo "=========================================="

# Check if cloudflared container exists and is running
echo "1. Cloudflared Container Status:"
echo "---------------------------------"
if docker ps | grep -q cloudflared; then
    echo "✅ Cloudflared container is running"
    CONTAINER_ID=$(docker ps | grep cloudflared | awk '{print $1}')
    echo "Container ID: $CONTAINER_ID"
    
    # Check container logs
    echo ""
    echo "2. Recent Cloudflared Logs:"
    echo "---------------------------------"
    docker logs --tail 20 $CONTAINER_ID 2>&1
    
    # Check if tunnel is connected
    echo ""
    echo "3. Tunnel Connection Status:"
    echo "---------------------------------"
    if docker logs $CONTAINER_ID 2>&1 | grep -q "Connection.*registered"; then
        echo "✅ Tunnel appears to be connected"
    else
        echo "❌ Tunnel may not be connected properly"
    fi
else
    echo "❌ Cloudflared container is NOT running"
    
    # Check if container exists but stopped
    if docker ps -a | grep -q cloudflared; then
        echo "⚠️  Container exists but is stopped"
        CONTAINER_ID=$(docker ps -a | grep cloudflared | awk '{print $1}')
        echo ""
        echo "Last logs from stopped container:"
        echo "---------------------------------"
        docker logs --tail 20 $CONTAINER_ID 2>&1
    fi
fi

# Check other services
echo ""
echo "4. Other Service Status:"
echo "---------------------------------"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "api|dashboard|worker|postgres|redis" || echo "No Dittofeed services found locally"

# Test internal connectivity
echo ""
echo "5. Internal Service Connectivity:"
echo "---------------------------------"
# Try to reach services internally if we're on the Docker host
if docker ps | grep -q "api"; then
    API_CONTAINER=$(docker ps | grep api | awk '{print $1}')
    echo -n "API Health: "
    docker exec $API_CONTAINER wget -q -O- http://localhost:3001/health 2>/dev/null && echo "✅ OK" || echo "❌ Failed"
fi

if docker ps | grep -q "dashboard"; then
    DASH_CONTAINER=$(docker ps | grep dashboard | awk '{print $1}')
    echo -n "Dashboard Health: "
    docker exec $DASH_CONTAINER wget -q -O- http://localhost:3000 2>/dev/null | head -c 100 && echo "... ✅ OK" || echo "❌ Failed"
fi

echo ""
echo "=========================================="
echo "📊 Summary"
echo "=========================================="
echo "If cloudflared is not running or not connected:"
echo "1. Check CF_TUNNEL_TOKEN is set in Coolify environment"
echo "2. Check Cloudflare Zero Trust dashboard for tunnel status"
echo "3. Ensure the tunnel routes are configured correctly"
echo ""
echo "Tunnel routes should be:"
echo "- communication-api.caramelme.com → http://api:3001"
echo "- communication-dashboard.caramelme.com → http://dashboard:3000"