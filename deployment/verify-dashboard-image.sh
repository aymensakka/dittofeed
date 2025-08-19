#!/bin/bash

echo "======================================"
echo "Verifying Dashboard Image and Config"
echo "======================================"
echo ""

# Find dashboard container
DASHBOARD=$(docker ps --format '{{.Names}}' | grep -i dashboard | head -1)

if [ -z "$DASHBOARD" ]; then
    echo "Dashboard container not found!"
    exit 1
fi

echo "Dashboard container: $DASHBOARD"
echo ""

echo "Step 1: Checking image digest..."
echo "---------------------------------"
IMAGE_ID=$(docker inspect $DASHBOARD --format='{{.Image}}')
echo "Container using image: $IMAGE_ID"

# Check if it's the new image
EXPECTED_DIGEST="sha256:411b01622f03d8a99971ca96f3428317e151cfe18a558134ad04b18dbfdb70a9"
ACTUAL_DIGEST=$(docker inspect $DASHBOARD --format='{{.Config.Image}}' | xargs docker inspect --format='{{.Id}}')
echo "Expected digest: $EXPECTED_DIGEST"
echo "Actual digest: $ACTUAL_DIGEST"

if [[ "$ACTUAL_DIGEST" == *"411b01622f03"* ]]; then
    echo "✅ Using the newly built multi-tenant image!"
else
    echo "❌ NOT using the new image!"
fi

echo ""
echo "Step 2: Checking build-time environment..."
echo "-------------------------------------------"
# Check what's actually in the built files
echo "Checking if Next.js was built with multi-tenant:"
docker exec $DASHBOARD sh -c "grep -r 'multi-tenant\|single-tenant' /app/.next/server/pages/ 2>/dev/null | head -5" || echo "Could not check build files"

echo ""
echo "Step 3: Checking runtime environment..."
echo "----------------------------------------"
docker exec $DASHBOARD env | grep -E "AUTH_MODE|WORKSPACE" | sort

echo ""
echo "Step 4: Checking next.config.js in container..."
echo "-------------------------------------------------"
echo "Looking for conflicting redirect:"
docker exec $DASHBOARD grep -A5 "redirects" /app/packages/dashboard/next.config.js 2>/dev/null || \
docker exec $DASHBOARD grep -A5 "redirects" /app/next.config.js 2>/dev/null || \
echo "Could not find next.config.js"

echo ""
echo "Step 5: Testing authentication endpoint..."
echo "-------------------------------------------"
DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD 2>/dev/null | head -c -1)
API=$(docker ps --format '{{.Names}}' | grep -i api | head -1)

if [ ! -z "$API" ]; then
    echo "Testing /dashboard/api/auth/session:"
    docker exec $API curl -s "http://$DASHBOARD_IP:3000/dashboard/api/auth/session" 2>/dev/null | head -100 || echo "Failed"
    echo ""
    echo "Testing /dashboard/auth/single-tenant:"
    docker exec $API curl -s "http://$DASHBOARD_IP:3000/dashboard/auth/single-tenant" 2>/dev/null | head -100 || echo "Failed"
fi

echo ""
echo "Step 6: Checking Next.js server output..."
echo "------------------------------------------"
docker logs $DASHBOARD --tail 50 2>&1 | grep -E "ready|started|error|Error" | tail -20

echo ""
echo "======================================"
echo "Diagnosis Complete"
echo "======================================"