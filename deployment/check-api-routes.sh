#!/bin/bash

echo "======================================"
echo "Checking API Routes and Configuration"
echo "======================================"
echo ""

PROJECT_ID="p0gcsc088cogco0cokco4404"
API=$(docker ps --format '{{.Names}}' | grep "api.*$PROJECT_ID" | head -1)

if [ -z "$API" ]; then
    echo "API container not found!"
    exit 1
fi

echo "API container: $API"
echo ""

echo "Step 1: Checking AUTH_MODE in API..."
echo "-------------------------------------"
AUTH_MODE=$(docker exec $API env | grep "^AUTH_MODE=" | cut -d= -f2)
echo "AUTH_MODE: $AUTH_MODE"

if [ "$AUTH_MODE" != "multi-tenant" ]; then
    echo "❌ CRITICAL: API is running in $AUTH_MODE mode, not multi-tenant!"
    echo "This explains why OAuth routes don't exist."
fi

echo ""
echo "Step 2: All AUTH-related environment variables..."
echo "--------------------------------------------------"
docker exec $API env | grep -E "AUTH|GOOGLE|OPENID" | sort

echo ""
echo "Step 3: Testing available routes..."
echo "------------------------------------"

API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API 2>/dev/null | head -c -1)
echo "API IP: $API_IP"
echo ""

# Test different auth endpoints
echo "Testing /health:"
docker exec $API curl -s "http://localhost:3001/health" | head -20
echo ""

echo "Testing /api/auth (single-tenant):"
docker exec $API curl -s "http://localhost:3001/api/auth" | head -20
echo ""

echo "Testing /api/public/auth/oauth2/initiate/google (multi-tenant):"
docker exec $API curl -s "http://localhost:3001/api/public/auth/oauth2/initiate/google" | head -20
echo ""

echo "Testing /api/public/healthcheck:"
docker exec $API curl -s "http://localhost:3001/api/public/healthcheck" | head -20
echo ""

echo "Step 4: Checking API startup logs..."
echo "-------------------------------------"
echo "Looking for route registration:"
docker logs $API 2>&1 | grep -E "route|Route|AUTH_MODE|Starting|multi-tenant|single-tenant" | tail -20

echo ""
echo "Step 5: Checking if API needs restart with correct env..."
echo "----------------------------------------------------------"

if [ "$AUTH_MODE" != "multi-tenant" ]; then
    echo "API needs to be restarted with AUTH_MODE=multi-tenant"
    echo ""
    echo "ACTION REQUIRED:"
    echo "1. Update Coolify environment for API service:"
    echo "   AUTH_MODE=multi-tenant"
    echo ""
    echo "2. Redeploy the API service in Coolify"
    echo ""
    echo "OR manually fix:"
    echo "docker stop $API"
    echo "docker run -e AUTH_MODE=multi-tenant [other options] [image]"
else
    echo "AUTH_MODE is correct. Checking if routes are properly registered..."
    
    # Check if it's actually using the env var
    docker logs $API 2>&1 | grep -i "auth.*mode" | tail -5
fi

echo ""
echo "======================================"
echo "Diagnosis"
echo "======================================"

if [ "$AUTH_MODE" != "multi-tenant" ]; then
    echo "❌ Root cause: API is running in $AUTH_MODE mode"
    echo "   OAuth routes only exist in multi-tenant mode"
    echo ""
    echo "Solution: Set AUTH_MODE=multi-tenant in Coolify for the API service"
else
    echo "⚠️  AUTH_MODE is set correctly but routes might not be registered"
    echo "   The API might need a restart to pick up the configuration"
fi