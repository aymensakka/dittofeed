#!/bin/bash
# Check Cloudflare tunnel routing

echo "=== Checking Cloudflare Tunnel Routing ==="
echo ""

# Check cloudflared container
echo "1. Cloudflared container status:"
CLOUDFLARED=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep cloudflared)
echo "$CLOUDFLARED"

echo ""
echo "2. Cloudflared logs (last 30 lines):"
CLOUDFLARED_CONTAINER=$(docker ps -q -f "name=cloudflared")
if [ -n "$CLOUDFLARED_CONTAINER" ]; then
    docker logs --tail 30 $CLOUDFLARED_CONTAINER 2>&1
else
    echo "   Cloudflared container not found"
fi

echo ""
echo "3. Container network aliases:"
echo "   API aliases:"
docker inspect api-p0gcsc088cogco0cokco4404-141944229613 --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}: {{range $v.Aliases}}{{.}} {{end}}{{end}}'

echo ""
echo "   Dashboard aliases:"
docker inspect dashboard-p0gcsc088cogco0cokco4404-141944268110 --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}: {{range $v.Aliases}}{{.}} {{end}}{{end}}'

echo ""
echo "4. Testing internal routing:"
echo "   From cloudflared to API:"
docker exec $CLOUDFLARED_CONTAINER wget -qO- http://api:3001/health 2>&1 || echo "   Failed to reach API as 'api'"
docker exec $CLOUDFLARED_CONTAINER wget -qO- http://api-p0gcsc088cogco0cokco4404-141944229613:3001/health 2>&1 || echo "   Failed with full name"

echo ""
echo "5. Network details:"
docker network inspect p0gcsc088cogco0cokco4404 2>/dev/null | python3 -m json.tool | grep -A5 -B5 "api\|dashboard" | head -50

echo ""
echo "=== Tunnel Configuration ==="
echo "The tunnel should route:"
echo "  communication-api.caramelme.com -> http://api:3001"
echo "  communication-dashboard.caramelme.com -> http://dashboard:3000"
echo ""
echo "Current container names that work:"
echo "  API: api-p0gcsc088cogco0cokco4404-141944229613 on port 3001"
echo "  Dashboard: dashboard-p0gcsc088cogco0cokco4404-141944268110 on port 3000"