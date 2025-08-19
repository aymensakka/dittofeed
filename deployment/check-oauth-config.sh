#!/bin/bash

# ==============================================================================
# Check OAuth Configuration for Multi-tenant Deployment
# ==============================================================================

set -e

echo "===================================================="
echo "OAuth Configuration Check"
echo "===================================================="
echo ""

# Find containers
DASHBOARD=$(docker ps --format '{{.Names}}' | grep dashboard | head -1)
API=$(docker ps --format '{{.Names}}' | grep api | grep -v adminapi | head -1)

if [ -z "$DASHBOARD" ]; then
    echo "❌ Dashboard container not found"
    exit 1
fi

echo "Step 1: Dashboard Environment Variables"
echo "----------------------------------------"
echo "Container: $DASHBOARD"
echo ""
docker exec $DASHBOARD env | grep -E "AUTH|GOOGLE|NEXTAUTH|NEXT_PUBLIC" | sort || echo "No AUTH variables found"

echo ""
echo "Step 2: API Environment Variables"
echo "----------------------------------------"
if [ ! -z "$API" ]; then
    echo "Container: $API"
    echo ""
    docker exec $API env | grep -E "AUTH|GOOGLE|NEXTAUTH" | sort || echo "No AUTH variables found"
else
    echo "⚠️  API container not found"
fi

echo ""
echo "Step 3: Checking OAuth Provider Configuration"
echo "----------------------------------------------"
POSTGRES=$(docker ps --format '{{.Names}}' | grep postgres | head -1)
if [ ! -z "$POSTGRES" ]; then
    echo "Checking AuthProvider table..."
    docker exec $POSTGRES psql -U dittofeed -d dittofeed -c \
        "SELECT type, enabled FROM \"AuthProvider\";" 2>/dev/null || echo "No auth providers configured"
    
    echo ""
    echo "Checking WorkspaceMember table..."
    docker exec $POSTGRES psql -U dittofeed -d dittofeed -c \
        "SELECT email, role FROM \"WorkspaceMember\" LIMIT 5;" 2>/dev/null || echo "No workspace members found"
fi

echo ""
echo "Step 4: Dashboard Authentication Mode"
echo "--------------------------------------"
# Check if dashboard is actually using multi-tenant mode
if [ ! -z "$DASHBOARD" ]; then
    echo "Checking dashboard process environment..."
    docker exec $DASHBOARD sh -c "ps aux | grep -E 'node|next' | head -1" || echo "Process not found"
    
    # Check if there's a .env file
    docker exec $DASHBOARD sh -c "if [ -f .env ]; then cat .env | grep -E 'AUTH|GOOGLE'; else echo 'No .env file'; fi" 2>/dev/null || true
    
    # Check next.config.js for auth mode
    docker exec $DASHBOARD sh -c "if [ -f next.config.js ]; then grep -A5 -B5 'AUTH_MODE\\|authMode' next.config.js | head -20; else echo 'next.config.js not found'; fi" 2>/dev/null || true
fi

echo ""
echo "Step 5: Quick Diagnosis"
echo "------------------------"

# Check critical variables
NEXT_PUBLIC_AUTH_MODE=$(docker exec $DASHBOARD env | grep "^NEXT_PUBLIC_AUTH_MODE=" | cut -d= -f2 || echo "NOT SET")
AUTH_MODE=$(docker exec $DASHBOARD env | grep "^AUTH_MODE=" | cut -d= -f2 || echo "NOT SET")
GOOGLE_CLIENT_ID=$(docker exec $DASHBOARD env | grep "^GOOGLE_CLIENT_ID=" | cut -d= -f2 | head -c 20 || echo "NOT SET")

echo "NEXT_PUBLIC_AUTH_MODE: $NEXT_PUBLIC_AUTH_MODE"
echo "AUTH_MODE: $AUTH_MODE"
echo "GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID}..."

if [ "$NEXT_PUBLIC_AUTH_MODE" != "multi-tenant" ]; then
    echo ""
    echo "⚠️  WARNING: NEXT_PUBLIC_AUTH_MODE is not set to 'multi-tenant'"
    echo "   This is required for OAuth authentication"
fi

if [ "$AUTH_MODE" != "multi-tenant" ]; then
    echo ""
    echo "⚠️  WARNING: AUTH_MODE is not set to 'multi-tenant'"
fi

echo ""
echo "===================================================="
echo "OAuth Configuration Check Complete"
echo "===================================================="
echo ""
echo "To fix anonymous mode:"
echo "1. Ensure these variables are set in Coolify:"
echo "   NEXT_PUBLIC_AUTH_MODE=multi-tenant"
echo "   AUTH_MODE=multi-tenant"
echo "   GOOGLE_CLIENT_ID=<your-client-id>"
echo "   GOOGLE_CLIENT_SECRET=<your-secret>"
echo "2. Redeploy the dashboard service from Coolify"
echo ""