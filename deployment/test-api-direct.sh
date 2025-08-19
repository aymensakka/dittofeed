#!/bin/bash
# Test API directly from the container

echo "=== Testing API Endpoints Directly ==="
echo ""

# Get API container name
API_CONTAINER="api-p0gcsc088cogco0cokco4404-141944229613"

echo "1. Testing health endpoint inside container:"
docker exec $API_CONTAINER curl -s http://localhost:3001/health || echo "Failed"

echo ""
echo "2. Testing OAuth endpoint inside container:"
docker exec $API_CONTAINER curl -s http://localhost:3001/api/public/auth/oauth2/initiate/google -I || echo "Failed"

echo ""
echo "3. Testing from host to container:"
# Get container IP
CONTAINER_IP=$(docker inspect $API_CONTAINER -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -n1)
echo "   Container IP: $CONTAINER_IP"
curl -s http://$CONTAINER_IP:3001/health || echo "Failed"

echo ""
echo "4. Testing OAuth initiate endpoint:"
curl -s http://$CONTAINER_IP:3001/api/public/auth/oauth2/initiate/google -I

echo ""
echo "5. Checking network routing:"
docker network ls | grep coolify
echo ""
docker inspect $API_CONTAINER --format='{{json .NetworkSettings.Networks}}' | python3 -m json.tool | head -20