#!/bin/bash

# ==============================================================================
# Test OAuth Flow and Debug Authentication
# ==============================================================================

set -e

echo "===================================================="
echo "OAuth Flow Testing and Debugging"
echo "===================================================="
echo ""

# Step 1: Test API endpoints
echo "Step 1: Testing API Endpoints"
echo "------------------------------"
echo -n "API Root: "
curl -s -o /dev/null -w "%{http_code}" https://communication-api.caramelme.com/ || echo "Failed"

echo -n "API Health: "
curl -s -o /dev/null -w "%{http_code}" https://communication-api.caramelme.com/api/health || echo "Failed"

echo -n "API Auth Providers: "
curl -s https://communication-api.caramelme.com/api/auth/providers 2>/dev/null | head -100 || echo "Failed"

echo ""
echo "Step 2: Testing Dashboard Endpoints"
echo "------------------------------------"
echo -n "Dashboard Root: "
curl -s -o /dev/null -w "%{http_code}" https://communication-dashboard.caramelme.com/ || echo "Failed"

echo -n "Dashboard /dashboard: "
curl -s -o /dev/null -w "%{http_code}" https://communication-dashboard.caramelme.com/dashboard || echo "Failed"

echo -n "Dashboard Auth Signin: "
curl -s -o /dev/null -w "%{http_code}" https://communication-dashboard.caramelme.com/api/auth/signin || echo "Failed"

echo ""
echo "Step 3: Testing OAuth Endpoints"
echo "--------------------------------"
echo -n "OAuth Providers: "
curl -s https://communication-dashboard.caramelme.com/api/auth/providers 2>/dev/null | head -100 || echo "Not found"

echo -n "OAuth Signin: "
curl -s https://communication-dashboard.caramelme.com/api/auth/signin 2>/dev/null | grep -o "<title>.*</title>" || echo "No signin page"

echo ""
echo "Step 4: Container Network Testing"
echo "----------------------------------"
DASHBOARD=$(docker ps --format '{{.Names}}' | grep dashboard | head -1)
API=$(docker ps --format '{{.Names}}' | grep api | grep -v adminapi | head -1)

if [ ! -z "$DASHBOARD" ] && [ ! -z "$API" ]; then
    echo "Testing internal connectivity..."
    
    # Test from dashboard to API
    docker exec $DASHBOARD sh -c "
        # Try to reach API using internal address
        echo -n 'Dashboard → API (internal): '
        nc -zv 172.27.0.8 3001 2>&1 | grep -q succeeded && echo '✓' || echo '✗'
    " 2>/dev/null || echo "Network test failed"
fi

echo ""
echo "Step 5: Check Authentication Configuration"
echo "------------------------------------------"
echo "Dashboard AUTH variables:"
docker exec $DASHBOARD env | grep -E "^AUTH_MODE=|^NEXT_PUBLIC_AUTH_MODE=|^AUTH_PROVIDER=" || echo "No auth vars"

echo ""
echo "API AUTH variables:"
docker exec $API env | grep -E "^AUTH_MODE=|^AUTH_PROVIDER=" || echo "No auth vars"

echo ""
echo "Step 6: Database Auth Configuration"
echo "------------------------------------"
POSTGRES=$(docker ps --format '{{.Names}}' | grep postgres | head -1)
if [ ! -z "$POSTGRES" ]; then
    echo "Checking AuthProvider table:"
    docker exec $POSTGRES psql -U dittofeed -d dittofeed -c \
        "SELECT * FROM \"AuthProvider\";" 2>/dev/null || echo "No AuthProvider entries"
    
    echo ""
    echo "Checking WorkspaceMember:"
    docker exec $POSTGRES psql -U dittofeed -d dittofeed -c \
        "SELECT email, role FROM \"WorkspaceMember\";" 2>/dev/null || echo "No members"
fi

echo ""
echo "===================================================="
echo "Diagnosis Summary"
echo "===================================================="
echo ""
echo "To access the dashboard:"
echo "1. Open: https://communication-dashboard.caramelme.com/dashboard"
echo "2. You should see either:"
echo "   - Google OAuth login button/redirect"
echo "   - Or an error message (check browser console)"
echo ""
echo "If you see 'anonymous@email.com':"
echo "   The dashboard is in anonymous mode (AUTH_MODE not applied)"
echo ""
echo "If you see 404:"
echo "   The dashboard can't find the workspace or routes"
echo ""
echo "Check browser Developer Tools:"
echo "   - Network tab for failed requests"
echo "   - Console for JavaScript errors"
echo ""