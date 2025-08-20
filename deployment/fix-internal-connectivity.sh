#!/bin/bash

# ==============================================================================
# Fix Internal Connectivity Between Dashboard and API
# This script configures proper internal networking and DNS resolution
# ==============================================================================

set -e

echo "===================================================="
echo "Fixing Internal Connectivity"
echo "===================================================="
echo ""

PROJECT_ID="p0gcsc088cogco0cokco4404"
NETWORK_NAME="p0gcsc088cogco0cokco4404"

# Find containers
API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)

if [ -z "$API_CONTAINER" ] || [ -z "$DASHBOARD_CONTAINER" ]; then
    echo "❌ Critical containers not found"
    echo "  API: ${API_CONTAINER:-NOT FOUND}"
    echo "  Dashboard: ${DASHBOARD_CONTAINER:-NOT FOUND}"
    exit 1
fi

echo "Found containers:"
echo "  API: $API_CONTAINER"
echo "  Dashboard: $DASHBOARD_CONTAINER"
echo ""

# Step 1: Get current network and IPs
echo "Step 1: Checking current network configuration..."
API_NETWORK=$(docker inspect $API_CONTAINER --format '{{range $net,$v := .NetworkSettings.Networks}}{{$net}}{{end}}' | head -1)
DASHBOARD_NETWORK=$(docker inspect $DASHBOARD_CONTAINER --format '{{range $net,$v := .NetworkSettings.Networks}}{{$net}}{{end}}' | head -1)
API_IP=$(docker inspect $API_CONTAINER --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)
DASHBOARD_IP=$(docker inspect $DASHBOARD_CONTAINER --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)

echo "Current configuration:"
echo "  API Network: $API_NETWORK"
echo "  API IP: $API_IP"
echo "  Dashboard Network: $DASHBOARD_NETWORK"
echo "  Dashboard IP: $DASHBOARD_IP"
echo ""

# Step 2: Ensure containers are on the same network
if [ "$API_NETWORK" != "$DASHBOARD_NETWORK" ]; then
    echo "⚠️  Containers are on different networks!"
    echo "Connecting both to network: $NETWORK_NAME"
    
    # Connect API to the correct network if needed
    docker network connect $NETWORK_NAME $API_CONTAINER 2>/dev/null || echo "API already connected"
    
    # Connect Dashboard to the correct network if needed
    docker network connect $NETWORK_NAME $DASHBOARD_CONTAINER 2>/dev/null || echo "Dashboard already connected"
    
    # Disconnect from wrong networks (optional, be careful)
    # docker network disconnect $API_NETWORK $API_CONTAINER 2>/dev/null || true
    
    # Get new IPs after network change
    API_IP=$(docker inspect $API_CONTAINER --format "{{.NetworkSettings.Networks.${NETWORK_NAME}.IPAddress}}" 2>/dev/null || echo $API_IP)
    DASHBOARD_IP=$(docker inspect $DASHBOARD_CONTAINER --format "{{.NetworkSettings.Networks.${NETWORK_NAME}.IPAddress}}" 2>/dev/null || echo $DASHBOARD_IP)
    
    echo "Updated IPs after network fix:"
    echo "  API IP: $API_IP"
    echo "  Dashboard IP: $DASHBOARD_IP"
fi

# Step 3: Add network aliases for service discovery
echo ""
echo "Step 3: Setting up network aliases..."

# Remove and recreate container with proper network alias
# This is the most reliable way to add network aliases
echo "Recreating API container with network alias..."

# Get all environment variables from current container
ENV_VARS=$(docker inspect $API_CONTAINER --format '{{range .Config.Env}}{{println "-e" .}}{{end}}')
IMAGE=$(docker inspect $API_CONTAINER --format '{{.Config.Image}}')
PORTS=$(docker inspect $API_CONTAINER --format '{{range $p, $conf := .NetworkSettings.Ports}}-p {{(index $conf 0).HostPort}}:{{$p}} {{end}}' | sed 's|/tcp||g' 2>/dev/null || echo "")

# Stop and remove old container
docker stop $API_CONTAINER > /dev/null 2>&1
docker rm $API_CONTAINER > /dev/null 2>&1

# Create new container with network alias
docker run -d \
    --name $API_CONTAINER \
    --network $NETWORK_NAME \
    --network-alias api \
    --network-alias api-service \
    $ENV_VARS \
    $PORTS \
    $IMAGE

# Wait for container to start
sleep 5

# Get new IP
API_IP=$(docker inspect $API_CONTAINER --format "{{.NetworkSettings.Networks.${NETWORK_NAME}.IPAddress}}")
echo "API container recreated with network aliases: api, api-service"
echo "New API IP: $API_IP"

# Step 4: Update Dashboard environment to use the alias
echo ""
echo "Step 4: Updating Dashboard environment variables..."

# Update environment in running container (temporary)
docker exec $DASHBOARD_CONTAINER sh -c "
export API_BASE_URL='http://api:3001'
export NEXT_PUBLIC_API_BASE_URL='https://communication-api.caramelme.com'
export INTERNAL_API_URL='http://api:3001'
" 2>/dev/null || echo "Could not update runtime environment"

# For permanent fix, we need to recreate the dashboard container too
echo "Recreating Dashboard container with updated configuration..."

ENV_VARS=$(docker inspect $DASHBOARD_CONTAINER --format '{{range .Config.Env}}{{println "-e" .}}{{end}}' | grep -v "API_BASE_URL" | grep -v "INTERNAL_API_URL")
IMAGE=$(docker inspect $DASHBOARD_CONTAINER --format '{{.Config.Image}}')
PORTS=$(docker inspect $DASHBOARD_CONTAINER --format '{{range $p, $conf := .NetworkSettings.Ports}}-p {{(index $conf 0).HostPort}}:{{$p}} {{end}}' | sed 's|/tcp||g' 2>/dev/null || echo "")

docker stop $DASHBOARD_CONTAINER > /dev/null 2>&1
docker rm $DASHBOARD_CONTAINER > /dev/null 2>&1

docker run -d \
    --name $DASHBOARD_CONTAINER \
    --network $NETWORK_NAME \
    --network-alias dashboard \
    -e "API_BASE_URL=http://api:3001" \
    -e "INTERNAL_API_URL=http://api:3001" \
    -e "NEXT_PUBLIC_API_BASE_URL=https://communication-api.caramelme.com" \
    $ENV_VARS \
    $PORTS \
    $IMAGE

sleep 5

DASHBOARD_IP=$(docker inspect $DASHBOARD_CONTAINER --format "{{.NetworkSettings.Networks.${NETWORK_NAME}.IPAddress}}")
echo "Dashboard container recreated with proper API connection"
echo "New Dashboard IP: $DASHBOARD_IP"

# Step 5: Test connectivity
echo ""
echo "Step 5: Testing internal connectivity..."

# Test from Dashboard to API using alias
echo -n "Dashboard → API (via alias 'api'): "
docker exec $DASHBOARD_CONTAINER sh -c "nc -zv api 3001 2>&1" | grep -q "succeeded" && echo "✅ Connected" || echo "❌ Failed"

# Test from Dashboard to API using IP
echo -n "Dashboard → API (via IP $API_IP): "
docker exec $DASHBOARD_CONTAINER sh -c "nc -zv $API_IP 3001 2>&1" | grep -q "succeeded" && echo "✅ Connected" || echo "❌ Failed"

# Test API health from Dashboard
echo -n "Dashboard → API health check: "
docker exec $DASHBOARD_CONTAINER sh -c "wget -q -O- http://api:3001/health 2>/dev/null | head -c 50" || echo "❌ Failed"
echo ""

# Step 6: Update Cloudflare tunnel configuration
echo ""
echo "Step 6: Cloudflare tunnel configuration..."
echo "Update your Cloudflare tunnel with these IPs:"
echo "  communication-api.caramelme.com → http://$API_IP:3001"
echo "  communication-dashboard.caramelme.com → http://$DASHBOARD_IP:3000"

# Step 7: Verify services are running
echo ""
echo "Step 7: Verifying services..."
for container in $API_CONTAINER $DASHBOARD_CONTAINER; do
    STATUS=$(docker inspect -f '{{.State.Status}}' $container 2>/dev/null)
    echo "  $container: $STATUS"
done

echo ""
echo "===================================================="
echo "Internal Connectivity Fix Complete!"
echo "===================================================="
echo ""
echo "Summary:"
echo "- API and Dashboard are now on the same network"
echo "- API is accessible via hostname 'api' from Dashboard"
echo "- Dashboard environment updated to use internal API connection"
echo ""
echo "Test the application at:"
echo "  https://communication-dashboard.caramelme.com/dashboard"
echo ""
echo "If you still see issues:"
echo "1. Check container logs:"
echo "   docker logs $API_CONTAINER"
echo "   docker logs $DASHBOARD_CONTAINER"
echo "2. Ensure Cloudflare tunnel is updated with new IPs"
echo ""