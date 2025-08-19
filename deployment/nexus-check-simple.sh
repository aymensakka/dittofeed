#!/bin/bash
# Simple Nexus Registry Health Check

echo "=== Nexus Registry Quick Check ==="
echo "Time: $(date)"
echo ""

# 1. Check if Nexus is running
echo "1. Checking Nexus process..."
if pgrep -f nexus > /dev/null 2>&1; then
    echo "   ✓ Nexus process is running"
else
    echo "   ✗ Nexus process NOT found"
fi

# 2. Check web interface
echo "2. Checking Nexus web UI..."
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8081" | grep -q "200\|302"; then
    echo "   ✓ Nexus web UI is responding"
else
    echo "   ✗ Nexus web UI not responding"
fi

# 3. Check Docker registry
echo "3. Checking Docker registry..."
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:5000/v2/" | grep -q "200\|401"; then
    echo "   ✓ Docker registry is responding"
else
    echo "   ✗ Docker registry not responding"
fi

# 4. Check disk space
echo "4. Checking disk space..."
DISK=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
echo "   Disk usage: ${DISK}%"
if [ "$DISK" -gt 90 ]; then
    echo "   ⚠ WARNING: Disk space critical!"
fi

# 5. Check memory
echo "5. Checking memory..."
MEM=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
echo "   Memory usage: ${MEM}%"

# 6. Test external access
echo "6. Testing external access..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://docker.reactmotion.com/v2/" 2>/dev/null)
echo "   Response code: $HTTP_CODE"
if [ "$HTTP_CODE" = "503" ]; then
    echo "   ✗ Registry returning 503 - Service Unavailable"
elif [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
    echo "   ✓ Registry is accessible"
else
    echo "   ? Unknown status"
fi

echo ""
echo "=== Quick Actions ==="
echo "To restart Nexus:"
echo "  sudo systemctl restart nexus"
echo ""
echo "To check logs:"
echo "  sudo tail -50 /opt/nexus/sonatype-work/nexus3/log/nexus.log"
echo ""
echo "To free disk space:"
echo "  docker system prune -af"