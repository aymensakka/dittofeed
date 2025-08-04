#!/bin/bash
# Health check script for Dittofeed services

echo "=========================================="
echo "🔍 Dittofeed Services Health Check"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration - Update these based on your deployment
API_URL="${API_BASE_URL:-https://api.dittofeed.reactmotion.com}"
DASHBOARD_URL="${DASHBOARD_URL:-https://dittofeed.reactmotion.com}"

# Function to check service health
check_service() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}
    
    echo -n "Testing $name... "
    
    response=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "$url" 2>/dev/null)
    
    if [ "$response" = "$expected_code" ]; then
        echo -e "${GREEN}✓ OK${NC} (HTTP $response)"
        return 0
    elif [ -n "$response" ]; then
        echo -e "${YELLOW}⚠ Warning${NC} (HTTP $response)"
        return 1
    else
        echo -e "${RED}✗ Failed${NC} (No response)"
        return 1
    fi
}

# Test API Health
echo ""
echo "1. API Service:"
echo "----------------------------------------"
check_service "API Health Endpoint" "$API_URL/health"
check_service "API Root" "$API_URL/"
check_service "API Version" "$API_URL/api/version" 

# Test Dashboard
echo ""
echo "2. Dashboard Service:"
echo "----------------------------------------"
check_service "Dashboard Homepage" "$DASHBOARD_URL"
check_service "Dashboard Login" "$DASHBOARD_URL/login"

# Test Database Connectivity via API
echo ""
echo "3. Database Connectivity (via API):"
echo "----------------------------------------"
echo -n "Testing database connection... "
db_test=$(curl -s -m 10 "$API_URL/health/db" 2>/dev/null)
if echo "$db_test" | grep -q "ok\|healthy\|connected"; then
    echo -e "${GREEN}✓ Connected${NC}"
else
    echo -e "${YELLOW}⚠ Check required${NC}"
fi

# Test Redis Connectivity via API
echo ""
echo "4. Redis Connectivity (via API):"
echo "----------------------------------------"
echo -n "Testing Redis connection... "
redis_test=$(curl -s -m 10 "$API_URL/health/redis" 2>/dev/null)
if echo "$redis_test" | grep -q "ok\|healthy\|connected"; then
    echo -e "${GREEN}✓ Connected${NC}"
else
    echo -e "${YELLOW}⚠ Check required${NC}"
fi

# Summary
echo ""
echo "=========================================="
echo "📊 Health Check Summary"
echo "=========================================="

# If running in Docker/Coolify environment, show container status
if command -v docker &> /dev/null; then
    echo ""
    echo "5. Container Status (if local):"
    echo "----------------------------------------"
    containers=$(docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -E "dittofeed|postgres|redis|api|dashboard|worker" | head -10)
    if [ -n "$containers" ]; then
        echo "$containers"
    else
        echo "No local Dittofeed containers found (may be running remotely)"
    fi
fi

echo ""
echo "Health check complete!"
echo ""
echo "ℹ️  Note: If services are deployed on Coolify, they may be accessible"
echo "   at the configured domain names rather than locally."