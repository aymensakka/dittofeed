#!/bin/bash

echo "=== COMPREHENSIVE WORKSPACE ISOLATION AUDIT ==="
echo ""

# Function to check if a controller file has proper workspace isolation
check_controller() {
    local file=$1
    local basename=$(basename "$file")
    
    echo "🔍 Auditing: $basename"
    
    # Check for database queries without workspace filter
    local bad_queries=$(grep -n "\.findFirst\|\.findMany\|\.delete.*schema\.\|\.update.*schema\." "$file" | grep -v "workspaceId" || true)
    if [ ! -z "$bad_queries" ]; then
        echo "  ⚠️  Potential unfiltered queries:"
        echo "$bad_queries" | sed 's/^/    /'
    fi
    
    # Check for proper request validation
    local has_workspace_validation=$(grep -n "workspaceId.*WorkspaceId\|WORKSPACE_ID_HEADER" "$file" || true)
    if [ -z "$has_workspace_validation" ]; then
        echo "  ❌ Missing workspace validation"
    else
        echo "  ✅ Has workspace validation"
    fi
    
    # Check for middleware or auth
    local has_auth=$(grep -n "authenticate\|requireAuth\|middleware" "$file" || true)
    if [ -z "$has_auth" ]; then
        echo "  ⚠️  No explicit auth middleware found"
    fi
    
    echo ""
}

echo "Checking all API controllers..."
echo ""

# Check each controller
for controller in /Users/aymensakka/dittofeed-multitenant/packages/api/src/controllers/*.ts; do
    if [[ "$controller" != *".test.ts" && "$controller" != *".deprecated"* ]]; then
        check_controller "$controller"
    fi
done

echo "=== CRITICAL ENDPOINTS ANALYSIS ==="
echo ""

echo "🔍 Checking for DELETE operations without workspace filters:"
grep -rn "\.delete(schema\." /Users/aymensakka/dittofeed-multitenant/packages/api/src/controllers/ --include="*.ts" | while read line; do
    file=$(echo "$line" | cut -d: -f1)
    linenum=$(echo "$line" | cut -d: -f2)
    context=$(sed -n "${linenum},$((linenum+5))p" "$file")
    if ! echo "$context" | grep -q "workspaceId"; then
        echo "❌ CRITICAL: $line"
        echo "   ^ Delete without workspace filter!"
    fi
done

echo ""
echo "🔍 Checking for UPDATE operations without workspace filters:"
grep -rn "\.update(schema\." /Users/aymensakka/dittofeed-multitenant/packages/api/src/controllers/ --include="*.ts" | while read line; do
    file=$(echo "$line" | cut -d: -f1)
    linenum=$(echo "$line" | cut -d: -f2)
    context=$(sed -n "${linenum},$((linenum+5))p" "$file")
    if ! echo "$context" | grep -q "workspaceId"; then
        echo "❌ CRITICAL: $line"
        echo "   ^ Update without workspace filter!"
    fi
done

echo ""
echo "🔍 Checking request context extraction:"
echo ""
echo "Looking for workspace context extraction patterns..."
grep -rn "request\." /Users/aymensakka/dittofeed-multitenant/packages/api/src/controllers/ --include="*.ts" | grep -i "workspace" | head -10

echo ""
echo "=== UI API CALL ANALYSIS ==="
echo ""
echo "🔍 Checking axiosInstance usage in dashboard:"
grep -rn "axiosInstance\." /Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/ --include="*.ts" --include="*.tsx" | grep -E "(post|put|delete|patch)" | head -10

echo ""
echo "🔍 Checking for workspaceId in request bodies/headers:"
grep -rn "workspaceId" /Users/aymensakka/dittofeed-multitenant/packages/dashboard/src/lib/ --include="*.ts" --include="*.tsx" | head -5

echo ""
echo "=== MIDDLEWARE AND AUTH CHECK ==="
echo ""
echo "🔍 Checking authentication middleware:"
find /Users/aymensakka/dittofeed-multitenant/packages/api/src -name "*.ts" -exec grep -l "authenticate\|requireAuth\|middleware" {} \;

echo ""
echo "Audit complete. Review findings above for security issues."