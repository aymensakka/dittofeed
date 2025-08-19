#!/bin/bash

echo "======================================"
echo "Fixing Authentication and API Issues"
echo "======================================"
echo ""

PROJECT_ID="p0gcsc088cogco0cokco4404"

# Find containers
API=$(docker ps --format '{{.Names}}' | grep "api.*$PROJECT_ID" | head -1)
DASHBOARD=$(docker ps --format '{{.Names}}' | grep "dashboard.*$PROJECT_ID" | head -1)
POSTGRES=$(docker ps -q -f name=postgres | head -1)

if [ -z "$API" ]; then
    echo "❌ API container not running!"
    # Try to start it
    API=$(docker ps -a --format '{{.Names}}' | grep "api.*$PROJECT_ID" | head -1)
    if [ ! -z "$API" ]; then
        docker start $API
        sleep 10
    fi
fi

echo "Containers found:"
echo "API: $API"
echo "Dashboard: $DASHBOARD"
echo ""

echo "Step 1: Checking API health..."
echo "-------------------------------"
if [ ! -z "$API" ]; then
    # Check if API is running
    if docker ps --format '{{.Names}}' | grep -q "$API"; then
        echo "API container is running"
        
        # Check API logs for errors
        echo "Recent API errors:"
        docker logs $API --tail 50 2>&1 | grep -i "error\|fatal\|critical" | tail -10
        
        # Check API health endpoint
        echo ""
        echo "Testing API health endpoint:"
        docker exec $API curl -s http://localhost:3001/health || echo "Health check failed"
        
        # Check database connection
        echo ""
        echo "Checking if API can connect to database:"
        docker exec $API sh -c 'echo "SELECT 1" | psql postgresql://dittofeed:dittofeed@postgres:5432/dittofeed' 2>&1 | head -5 || echo "DB connection failed"
    else
        echo "❌ API container is not running!"
    fi
fi

echo ""
echo "Step 2: Checking authentication configuration..."
echo "-------------------------------------------------"

# Check API environment
echo "API Authentication Environment:"
docker exec $API env | grep -E "AUTH|GOOGLE|OPENID|SESSION" | sort

echo ""
echo "Step 3: Checking workspace and bootstrap..."
echo "--------------------------------------------"

# Check if workspace exists
if [ ! -z "$POSTGRES" ]; then
    echo "Workspaces in database:"
    docker exec $POSTGRES psql -U dittofeed -d dittofeed -c "SELECT id, name, type, status FROM \"Workspace\";" 2>/dev/null
    
    echo ""
    echo "Workspace members:"
    docker exec $POSTGRES psql -U dittofeed -d dittofeed -c "SELECT * FROM \"WorkspaceMember\" LIMIT 5;" 2>/dev/null || echo "No members found"
fi

echo ""
echo "Step 4: Testing authentication flow..."
echo "---------------------------------------"

API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API 2>/dev/null | head -c -1)
DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD 2>/dev/null | head -c -1)

echo "API IP: $API_IP"
echo "Dashboard IP: $DASHBOARD_IP"

# Test internal auth endpoints
echo ""
echo "Testing internal API auth endpoint:"
docker exec $DASHBOARD curl -s "http://$API_IP:3001/api/public/auth/oauth2/initiate/google" 2>&1 | head -20

echo ""
echo "Step 5: Fixing Cloudflare tunnel configuration..."
echo "--------------------------------------------------"

# Update cloudflare tunnel
CLOUDFLARED=$(docker ps --format '{{.Names}}' | grep -i cloudflared | head -1)
if [ ! -z "$CLOUDFLARED" ]; then
    cat > /tmp/cloudflared-config.yml << EOF
tunnel: auto
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: communication-api.caramelme.com
    service: http://${API_IP}:3001
    originRequest:
      noTLSVerify: true
      
  - hostname: communication-dashboard.caramelme.com
    service: http://${DASHBOARD_IP}:3000
    originRequest:
      noTLSVerify: true
      
  - service: http_status:404
EOF
    
    docker cp /tmp/cloudflared-config.yml ${CLOUDFLARED}:/etc/cloudflared/config.yml
    docker restart ${CLOUDFLARED}
    echo "✅ Cloudflare tunnel updated"
    
    sleep 5
fi

echo ""
echo "Step 6: Restarting API if needed..."
echo "------------------------------------"

# Check if API needs restart
API_UPTIME=$(docker inspect -f '{{.State.StartedAt}}' $API 2>/dev/null)
echo "API started at: $API_UPTIME"

# If API has errors, restart it
if docker logs $API --tail 20 2>&1 | grep -q "Error\|FATAL\|Cannot"; then
    echo "API has errors, restarting..."
    docker restart $API
    echo "Waiting for API to start..."
    sleep 15
fi

echo ""
echo "Step 7: Final tests..."
echo "-----------------------"

echo "Testing external endpoints:"
echo ""

echo -n "API Health: "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://communication-api.caramelme.com/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ HTTP $HTTP_CODE"
else
    echo "❌ HTTP $HTTP_CODE"
fi

echo -n "OAuth Initiate: "
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" "https://communication-api.caramelme.com/api/public/auth/oauth2/initiate/google" 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
if [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "200" ]; then
    echo "✅ HTTP $HTTP_CODE"
    echo "OAuth redirect URL:"
    echo "$RESPONSE" | grep -i "location:" || echo "$RESPONSE" | head -5
else
    echo "❌ HTTP $HTTP_CODE"
    echo "Response:"
    echo "$RESPONSE" | head -20
fi

echo ""
echo "======================================"
echo "Summary"
echo "======================================"

if [ "$HTTP_CODE" = "502" ]; then
    echo ""
    echo "❌ API is not responding properly. Possible issues:"
    echo "1. API container crashed after starting"
    echo "2. Database connection issues"
    echo "3. Missing environment variables"
    echo ""
    echo "Check API logs:"
    echo "docker logs $API --tail 100"
else
    echo ""
    echo "✅ API appears to be working"
    echo ""
    echo "To authenticate:"
    echo "1. Go to: https://communication-api.caramelme.com/api/public/auth/oauth2/initiate/google"
    echo "2. Sign in with Google"
    echo "3. You'll be redirected to the dashboard"
fi