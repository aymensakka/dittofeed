#!/bin/bash

# ==============================================================================
# Check for Duplicate Dittofeed Instances
# This script identifies all Dittofeed-related containers and groups them
# ==============================================================================

set -e

echo "====================================================="
echo "Checking for Duplicate Dittofeed Instances"
echo "====================================================="
echo ""

# Function to check container details
check_container_group() {
    local group_name=$1
    local pattern=$2
    
    echo "Checking $group_name containers..."
    echo "Pattern: $pattern"
    echo "----------------------------------------"
    
    containers=$(docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.CreatedAt}}" | grep -E "$pattern" 2>/dev/null || true)
    
    if [ -z "$containers" ]; then
        echo "  No containers found"
    else
        echo "$containers"
    fi
    echo ""
}

# Check Coolify-managed containers (with project ID)
echo "1. COOLIFY-MANAGED CONTAINERS (Project: p0gcsc088cogco0cokco4404)"
echo "================================================================="
check_container_group "Coolify API" "api.*p0gcsc088cogco0cokco4404"
check_container_group "Coolify Dashboard" "dashboard.*p0gcsc088cogco0cokco4404"
check_container_group "Coolify Worker" "worker.*p0gcsc088cogco0cokco4404"
check_container_group "Coolify Postgres" "postgres.*p0gcsc088cogco0cokco4404"
check_container_group "Coolify Redis" "redis.*p0gcsc088cogco0cokco4404"
check_container_group "Coolify Temporal" "temporal.*p0gcsc088cogco0cokco4404"
check_container_group "Coolify ClickHouse" "clickhouse.*p0gcsc088cogco0cokco4404"
check_container_group "Coolify Cloudflared" "cloudflared.*p0gcsc088cogco0cokco4404"

# Check local test containers
echo "2. LOCAL TEST CONTAINERS (dittofeed-multitenant-*)"
echo "================================================================="
check_container_group "Local Test" "dittofeed-multitenant"

# Check other Dittofeed containers
echo "3. OTHER DITTOFEED CONTAINERS"
echo "================================================================="
check_container_group "Dashboard variants" "dashboard-(fixed|test|dev)"
check_container_group "API variants" "api-(fixed|test|dev)"
check_container_group "Generic Dittofeed" "dittofeed(?!-multitenant)"

# Summary of all Dittofeed-related containers
echo "4. SUMMARY - ALL DITTOFEED-RELATED CONTAINERS"
echo "================================================================="
echo "Active (Running) containers:"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -E "dittofeed|communication|p0gcsc088cogco0cokco4404" | head -20 || echo "  None found"

echo ""
echo "Stopped containers:"
docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -E "dittofeed|communication|p0gcsc088cogco0cokco4404" | head -20 || echo "  None found"

# Check for port conflicts
echo ""
echo "5. PORT USAGE CHECK"
echo "================================================================="
echo "Checking for services on key ports..."
echo ""
echo "Port 3000 (Dashboard):"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep "3000" || echo "  No containers using port 3000"
echo ""
echo "Port 3001 (API):"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep "3001" || echo "  No containers using port 3001"
echo ""
echo "Port 5432 (PostgreSQL):"
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep "5432" || echo "  No containers using port 5432"

# Check docker networks
echo ""
echo "6. DOCKER NETWORKS"
echo "================================================================="
echo "Networks with Dittofeed containers:"
for network in $(docker network ls --format "{{.Name}}"); do
    containers=$(docker network inspect $network --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null | grep -E "dittofeed|communication|p0gcsc088cogco0cokco4404" 2>/dev/null || true)
    if [ ! -z "$containers" ]; then
        echo "Network: $network"
        echo "  Containers: $containers"
    fi
done

# Recommendations
echo ""
echo "7. RECOMMENDATIONS"
echo "================================================================="

# Count different groups
COOLIFY_COUNT=$(docker ps -a --format "{{.Names}}" | grep -c "p0gcsc088cogco0cokco4404" || echo "0")
LOCAL_TEST_COUNT=$(docker ps -a --format "{{.Names}}" | grep -c "dittofeed-multitenant" || echo "0")
OTHER_COUNT=$(docker ps -a --format "{{.Names}}" | grep -E "dittofeed|dashboard-fixed|api-fixed" | grep -v "p0gcsc088cogco0cokco4404" | grep -v "dittofeed-multitenant" | wc -l | tr -d ' ')

echo "Found:"
echo "  - Coolify containers: $COOLIFY_COUNT"
echo "  - Local test containers: $LOCAL_TEST_COUNT"
echo "  - Other Dittofeed containers: $OTHER_COUNT"
echo ""

if [ "$COOLIFY_COUNT" -gt 0 ] && [ "$LOCAL_TEST_COUNT" -gt 0 ]; then
    echo "⚠️  WARNING: Both Coolify and local test containers are present!"
    echo "   This may cause conflicts. Consider stopping one set."
    echo ""
    echo "   To stop local test containers:"
    echo "   docker stop \$(docker ps -q --filter name=dittofeed-multitenant)"
    echo ""
    echo "   To remove local test containers:"
    echo "   docker rm \$(docker ps -aq --filter name=dittofeed-multitenant)"
fi

if [ "$OTHER_COUNT" -gt 0 ]; then
    echo "⚠️  Found other Dittofeed containers that may be from previous tests."
    echo "   Review and remove if not needed."
fi

echo ""
echo "====================================================="
echo "Check complete!"
echo "====================================================="