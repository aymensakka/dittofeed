#!/bin/bash
# Check container logs for Dittofeed deployment

echo "=== Checking Dittofeed Container Logs ==="
echo ""

# Check API logs
echo "=== API Container Logs ==="
API_CONTAINER="api-p0gcsc088cogco0cokco4404-141944229613"
echo "Container: $API_CONTAINER"
docker logs --tail 50 $API_CONTAINER 2>&1
echo ""

# Check Dashboard logs
echo "=== Dashboard Container Logs ==="
DASHBOARD_CONTAINER="dashboard-p0gcsc088cogco0cokco4404-141944268110"
echo "Container: $DASHBOARD_CONTAINER"
docker logs --tail 50 $DASHBOARD_CONTAINER 2>&1
echo ""

# Check Worker logs
echo "=== Worker Container Logs ==="
WORKER_CONTAINER="worker-p0gcsc088cogco0cokco4404-141944296571"
echo "Container: $WORKER_CONTAINER"
docker logs --tail 30 $WORKER_CONTAINER 2>&1
echo ""

# Check health status
echo "=== Health Check Status ==="
echo "API Health:"
docker inspect $API_CONTAINER --format='{{json .State.Health}}' | python3 -m json.tool 2>/dev/null || echo "No health check data"
echo ""
echo "Dashboard Health:"
docker inspect $DASHBOARD_CONTAINER --format='{{json .State.Health}}' | python3 -m json.tool 2>/dev/null || echo "No health check data"