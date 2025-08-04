#!/bin/bash
# Complete deployment test script

echo "==========================================="
echo "🔍 Dittofeed Deployment Test"
echo "==========================================="
echo ""

# Test environment variables
API_URL="${API_URL:-https://api.com.caramelme.com}"
DASHBOARD_URL="${DASHBOARD_URL:-https://dashboard.com.caramelme.com}"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to test URL
test_url() {
    local url=$1
    local name=$2
    echo -n "Testing $name ($url): "
    
    response=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 10 "$url" 2>/dev/null)
    
    if [ "$response" = "200" ] || [ "$response" = "302" ] || [ "$response" = "304" ]; then
        echo -e "${GREEN}✅ OK (HTTP $response)${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed (HTTP $response)${NC}"
        return 1
    fi
}

# Function to test internal service
test_internal() {
    local container=$1
    local port=$2
    local path=$3
    local name=$4
    
    echo -n "Testing $name internally: "
    
    container_id=$(docker ps -q -f name=$container | head -1)
    if [ -z "$container_id" ]; then
        echo -e "${RED}❌ Container not found${NC}"
        return 1
    fi
    
    if docker exec $container_id wget -q -O- "http://localhost:$port$path" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed${NC}"
        return 1
    fi
}

echo "1. Container Status:"
echo "---------------------------------"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "postgres|redis|api|worker|dashboard|cloudflared" || echo "No containers found"

echo ""
echo "2. Internal Health Checks:"
echo "---------------------------------"
test_internal "api" "3001" "/health" "API Health"
test_internal "dashboard" "3000" "/" "Dashboard"

echo ""
echo "3. Database Connection:"
echo "---------------------------------"
postgres_id=$(docker ps -q -f name=postgres | head -1)
if [ -n "$postgres_id" ]; then
    echo -n "PostgreSQL database 'dittofeed': "
    if docker exec $postgres_id psql -U dittofeed -d dittofeed -c "SELECT 1" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Connected${NC}"
    else
        echo -e "${RED}❌ Not accessible${NC}"
        echo "  Attempting to create database..."
        docker exec $postgres_id psql -U postgres -c "CREATE DATABASE dittofeed;" 2>/dev/null && echo "  Database created!" || echo "  Database creation failed"
    fi
fi

echo ""
echo "4. External Access Tests:"
echo "---------------------------------"
test_url "$API_URL/health" "API External"
test_url "$DASHBOARD_URL" "Dashboard External"

echo ""
echo "5. Cloudflare Tunnel Status:"
echo "---------------------------------"
cloudflared_id=$(docker ps -q -f name=cloudflared | head -1)
if [ -n "$cloudflared_id" ]; then
    echo -n "Tunnel connection: "
    if docker logs $cloudflared_id 2>&1 | tail -20 | grep -q "Registered tunnel connection"; then
        echo -e "${GREEN}✅ Connected${NC}"
        echo "Routes configured:"
        echo "  - api.com.caramelme.com → api:3001"
        echo "  - dashboard.com.caramelme.com → dashboard:3000"
    else
        echo -e "${RED}❌ Not connected${NC}"
    fi
else
    echo -e "${RED}❌ Cloudflared container not found${NC}"
fi

echo ""
echo "==========================================="
echo "📊 Summary"
echo "==========================================="

# Count successes
total_tests=0
passed_tests=0

# Re-run tests silently for summary
test_internal "api" "3001" "/health" "API" > /dev/null 2>&1 && ((passed_tests++))
((total_tests++))

test_internal "dashboard" "3000" "/" "Dashboard" > /dev/null 2>&1 && ((passed_tests++))
((total_tests++))

test_url "$API_URL/health" "API External" > /dev/null 2>&1 && ((passed_tests++))
((total_tests++))

test_url "$DASHBOARD_URL" "Dashboard External" > /dev/null 2>&1 && ((passed_tests++))
((total_tests++))

echo "Tests passed: $passed_tests/$total_tests"

if [ $passed_tests -eq $total_tests ]; then
    echo -e "${GREEN}✅ Deployment is fully operational!${NC}"
    echo ""
    echo "Access your Dittofeed instance at:"
    echo "  Dashboard: $DASHBOARD_URL"
    echo "  API: $API_URL"
else
    echo -e "${RED}⚠️  Some services need attention${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check container logs in Coolify"
    echo "2. Verify environment variables are set correctly"
    echo "3. Ensure Cloudflare tunnel routes are configured"
    echo "4. Check if database 'dittofeed' exists"
fi