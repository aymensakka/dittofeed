#!/bin/bash
# Generate a debug report for Dittofeed deployment
# This script collects diagnostic information without exposing secrets

echo "=================================================="
echo "📊 Dittofeed Deployment Debug Report"
echo "Generated at: $(date)"
echo "=================================================="
echo ""

# System Information
echo "=== SYSTEM INFORMATION ==="
echo "Hostname: $(hostname)"
echo "OS: $(uname -a)"
echo "Docker Version: $(docker --version)"
echo "Docker Compose Version: $(docker compose version 2>/dev/null || echo 'Not installed')"
echo ""

# Container Status
echo "=== CONTAINER STATUS ==="
echo "Running Containers:"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAME|api|dashboard|worker|postgres|redis|cloudflared" | sed 's/docker.reactmotion.com\/[^\/]*\//[REGISTRY]\//g'
echo ""

echo "All Containers (including stopped):"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.RestartCount}}" | grep -E "NAME|api|dashboard|worker|postgres|redis|cloudflared" | head -10
echo ""

# Container Health
echo "=== CONTAINER HEALTH CHECK ==="
for container in $(docker ps --format "{{.Names}}" | grep -E "api|dashboard|worker|postgres|redis|cloudflared"); do
    echo -n "$container: "
    docker inspect $container --format '{{.State.Health.Status}}' 2>/dev/null || echo "No health check"
done
echo ""

# Network Information
echo "=== NETWORK CONFIGURATION ==="
echo "Docker Networks:"
docker network ls | grep -E "NETWORK|coolify|dittofeed|bridge"
echo ""

echo "Container Network Details:"
for container in $(docker ps --format "{{.Names}}" | grep -E "api|dashboard|cloudflared" | head -3); do
    echo "$container:"
    docker inspect $container --format '{{range .NetworkSettings.Networks}}  Network: {{.NetworkID | printf "%.12s"}} IP: {{.IPAddress}}{{end}}' 2>/dev/null
done
echo ""

# Database Status
echo "=== DATABASE STATUS ==="
POSTGRES_CONTAINER=$(docker ps | grep postgres | awk '{print $1}')
if [ ! -z "$POSTGRES_CONTAINER" ]; then
    echo "PostgreSQL Tables:"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\dt" 2>&1 | grep -E "List of relations|No relations|Workspace|Secret|Journey" | head -10
    echo ""
    echo "Database Size:"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT pg_database_size('dittofeed')/1024/1024 as size_mb;" 2>&1 | grep -E "size_mb|------" -A 1
else
    echo "PostgreSQL container not found"
fi
echo ""

# Environment Variables (sanitized)
echo "=== ENVIRONMENT VARIABLES (Sanitized) ==="
API_CONTAINER=$(docker ps | grep "api-" | awk '{print $1}')
if [ ! -z "$API_CONTAINER" ]; then
    echo "API Environment Variables:"
    docker exec $API_CONTAINER env | grep -E "NODE_ENV|AUTH_MODE|BOOTSTRAP|MULTITENANCY|DATABASE_URL|API_BASE_URL|DASHBOARD_URL|REDIS_URL|WORKER_ID|CLICKHOUSE|TEMPORAL" | sed -E 's/(PASSWORD|SECRET|KEY|TOKEN)=[^[:space:]]*/\1=[REDACTED]/g' | sed -E 's/postgresql:\/\/[^@]*@/postgresql:\/\/[REDACTED]@/g' | sort
    echo ""
fi

DASHBOARD_CONTAINER=$(docker ps | grep "dashboard-" | awk '{print $1}')
if [ ! -z "$DASHBOARD_CONTAINER" ]; then
    echo "Dashboard Environment Variables:"
    docker exec $DASHBOARD_CONTAINER env | grep -E "NODE_ENV|AUTH_MODE|NEXTAUTH_URL|NEXT_PUBLIC|GOOGLE_CLIENT_ID" | sed -E 's/(PASSWORD|SECRET|KEY|TOKEN)=[^[:space:]]*/\1=[REDACTED]/g' | sed -E 's/GOOGLE_CLIENT_SECRET=[^[:space:]]*/GOOGLE_CLIENT_SECRET=[REDACTED]/g' | sort
    echo ""
fi

# Recent Logs (errors only)
echo "=== RECENT ERROR LOGS ==="
echo "API Errors (last 10):"
if [ ! -z "$API_CONTAINER" ]; then
    docker logs $API_CONTAINER 2>&1 | grep -i "error\|failed\|exception" | tail -10 | sed -E 's/(password|secret|token)=[^[:space:]]*/\1=[REDACTED]/gi'
fi
echo ""

echo "Dashboard Errors (last 10):"
if [ ! -z "$DASHBOARD_CONTAINER" ]; then
    docker logs $DASHBOARD_CONTAINER 2>&1 | grep -i "error\|failed\|exception" | tail -10 | sed -E 's/(password|secret|token)=[^[:space:]]*/\1=[REDACTED]/gi'
fi
echo ""

# Cloudflare Tunnel Status
echo "=== CLOUDFLARE TUNNEL STATUS ==="
CLOUDFLARED_CONTAINER=$(docker ps | grep cloudflared | awk '{print $1}')
if [ ! -z "$CLOUDFLARED_CONTAINER" ]; then
    echo "Tunnel Connection Status:"
    docker logs $CLOUDFLARED_CONTAINER 2>&1 | grep -E "Registered tunnel|Connection.*registered|error" | tail -5 | sed -E 's/token:[^[:space:]]*/token:[REDACTED]/g'
    echo ""
    echo "Configured Routes:"
    docker logs $CLOUDFLARED_CONTAINER 2>&1 | grep "Updated to new configuration" -A 1 | tail -5
else
    echo "Cloudflared container not found"
fi
echo ""

# Endpoint Tests
echo "=== ENDPOINT CONNECTIVITY ==="
echo "Internal Connectivity Tests:"
if [ ! -z "$API_CONTAINER" ]; then
    echo -n "API → PostgreSQL: "
    docker exec $API_CONTAINER ping -c 1 postgres >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed"
    echo -n "API → Redis: "
    docker exec $API_CONTAINER ping -c 1 redis >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed"
fi

if [ ! -z "$DASHBOARD_CONTAINER" ] && [ ! -z "$API_CONTAINER" ]; then
    echo -n "Dashboard → API: "
    docker exec $DASHBOARD_CONTAINER ping -c 1 $(docker inspect $API_CONTAINER --format '{{.Name}}' | sed 's/\///') >/dev/null 2>&1 && echo "✅ OK" || echo "❌ Failed"
fi
echo ""

echo "External Endpoint Status:"
echo -n "API (https://communication-api.caramelme.com/api): "
curl -s -o /dev/null -w "%{http_code}" https://communication-api.caramelme.com/api 2>/dev/null || echo "Failed to connect"
echo ""
echo -n "Dashboard (https://communication-dashboard.caramelme.com/): "
curl -s -o /dev/null -w "%{http_code}" https://communication-dashboard.caramelme.com/ 2>/dev/null || echo "Failed to connect"
echo ""

# Resource Usage
echo "=== RESOURCE USAGE ==="
echo "Container Resource Usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" | grep -E "CONTAINER|api|dashboard|worker|postgres|redis" | head -10
echo ""

# Disk Usage
echo "=== DISK USAGE ==="
echo "Docker Disk Usage:"
docker system df
echo ""

# Recent Deployments
echo "=== RECENT DEPLOYMENTS ==="
echo "Container Start Times:"
docker ps --format "table {{.Names}}\t{{.CreatedAt}}\t{{.RunningFor}}" | grep -E "NAMES|api|dashboard|worker|postgres|redis|cloudflared" | head -10
echo ""

# Summary
echo "=== SUMMARY ==="
echo "Issues Detected:"
ISSUES=0

# Check for unhealthy containers
UNHEALTHY=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" | wc -l)
if [ $UNHEALTHY -gt 0 ]; then
    echo "- $UNHEALTHY containers are unhealthy"
    ISSUES=$((ISSUES + 1))
fi

# Check for restarting containers
RESTARTING=$(docker ps --filter "status=restarting" --format "{{.Names}}" | wc -l)
if [ $RESTARTING -gt 0 ]; then
    echo "- $RESTARTING containers are restarting"
    ISSUES=$((ISSUES + 1))
fi

# Check database
if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "- PostgreSQL container not found"
    ISSUES=$((ISSUES + 1))
else
    TABLES=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\dt" 2>&1 | grep -c "rows)")
    if [ $TABLES -eq 0 ]; then
        echo "- Database has no tables"
        ISSUES=$((ISSUES + 1))
    fi
fi

if [ $ISSUES -eq 0 ]; then
    echo "✅ No major issues detected"
else
    echo ""
    echo "Total issues: $ISSUES"
fi

echo ""
echo "=================================================="
echo "Report generated at: $(date)"
echo "=================================================="