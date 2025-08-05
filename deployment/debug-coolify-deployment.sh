#!/bin/bash
# Debug Coolify deployment issues

echo "=== Debugging Coolify Deployment ==="
echo ""

# Check for any stopped containers
echo "1. Checking for stopped containers:"
echo "----------------------------------------"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.State}}" | grep -E "api|dashboard|worker|postgres" | head -10

echo ""
echo "2. Docker Compose files in current directory:"
echo "----------------------------------------"
ls -la | grep docker-compose

echo ""
echo "3. Checking Coolify project containers:"
echo "----------------------------------------"
# Coolify uses specific naming patterns
docker ps -a | grep -E "p0gcsc088cogco0cokco4404|s0ssgksskow44wgwk8w880cc" | head -20

echo ""
echo "4. Recent container logs (if any failed):"
echo "----------------------------------------"
# Get logs from any recently stopped containers
for container in $(docker ps -a --format "{{.Names}}" | grep -E "api|dashboard|worker|postgres" | head -5); do
    echo "Logs for $container:"
    docker logs --tail 10 $container 2>&1 | head -20
    echo "---"
done

echo ""
echo "5. Docker volumes:"
echo "----------------------------------------"
docker volume ls | grep -E "postgres|redis"

echo ""
echo "=== Recommended Actions ==="
echo "1. Check Coolify deployment status in the UI"
echo "2. Look for error messages in deployment logs"
echo "3. Verify all environment variables are set"
echo "4. Try redeploying from Coolify UI"
echo ""
echo "To manually start services:"
echo "  docker compose -f docker-compose.coolify.yaml up -d"