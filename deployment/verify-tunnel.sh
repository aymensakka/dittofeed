#!/bin/bash
# Verify Cloudflare tunnel and service connectivity

echo "=== Verifying Deployment ==="
echo ""

# Check container status
echo "1. Container Status:"
echo "-------------------"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "api|dashboard|cloudflared|postgres|redis|worker" | sort

echo ""
echo "2. Cloudflare Tunnel Logs:"
echo "-------------------------"
CLOUDFLARED_CONTAINER=$(docker ps -q -f name=cloudflared | head -1)
if [ -n "$CLOUDFLARED_CONTAINER" ]; then
    docker logs --tail 20 $CLOUDFLARED_CONTAINER 2>&1 | grep -E "Registered|route|config|error|ERROR"
else
    echo "❌ Cloudflared container not found"
fi

echo ""
echo "3. Internal Service Tests:"
echo "-------------------------"
# Test API
API_CONTAINER=$(docker ps -q -f name=api | head -1)
if [ -n "$API_CONTAINER" ]; then
    echo -n "API health check: "
    if docker exec $API_CONTAINER wget -q -O- http://localhost:3001/health 2>/dev/null; then
        echo " ✅"
    else
        echo " ❌"
        echo "API logs:"
        docker logs --tail 10 $API_CONTAINER 2>&1
    fi
fi

# Test Dashboard
DASH_CONTAINER=$(docker ps -q -f name=dashboard | head -1)
if [ -n "$DASH_CONTAINER" ]; then
    echo -n "Dashboard check: "
    if docker exec $DASH_CONTAINER wget -q -O- http://localhost:3000 2>/dev/null | grep -q "title"; then
        echo "✅"
    else
        echo "❌"
    fi
fi

echo ""
echo "4. Network Connectivity from Cloudflared:"
echo "----------------------------------------"
if [ -n "$CLOUDFLARED_CONTAINER" ]; then
    # Get container names
    API_NAME=$(docker ps --format "{{.Names}}" | grep api | head -1)
    DASH_NAME=$(docker ps --format "{{.Names}}" | grep dashboard | head -1)
    
    echo "API container name: $API_NAME"
    echo "Dashboard container name: $DASH_NAME"
    
    # Test connectivity
    echo -n "Can cloudflared reach API? "
    if docker exec $CLOUDFLARED_CONTAINER ping -c 1 ${API_NAME} &>/dev/null; then
        echo "✅ YES"
        # Try to get the service
        docker exec $CLOUDFLARED_CONTAINER wget -q -O- http://${API_NAME}:3001/health 2>&1 | head -20 || echo "HTTP request failed"
    else
        echo "❌ NO - Network issue"
    fi
    
    echo -n "Can cloudflared reach Dashboard? "
    if docker exec $CLOUDFLARED_CONTAINER ping -c 1 ${DASH_NAME} &>/dev/null; then
        echo "✅ YES"
    else
        echo "❌ NO - Network issue"
    fi
fi

echo ""
echo "=== CLOUDFLARE TUNNEL CONFIGURATION ==="
echo ""
echo "In Cloudflare Zero Trust Dashboard, your tunnel routes should be:"
echo ""
echo "Route 1:"
echo "  Subdomain: api"
echo "  Domain: com.caramelme.com"
echo "  Service: http://${API_NAME}:3001"
echo ""
echo "Route 2:"
echo "  Subdomain: dashboard"
echo "  Domain: com.caramelme.com"
echo "  Service: http://${DASH_NAME}:3000"
echo ""
echo "Use the exact container names shown above!"