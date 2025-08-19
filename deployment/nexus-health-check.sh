#!/bin/bash
# Nexus Registry Health Check Script
# Run this on the server hosting the Nexus Docker Registry

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Configuration
NEXUS_URL="http://localhost:8081"  # Internal Nexus URL
DOCKER_PORT="5000"  # Docker registry port (adjust if different)
NGINX_PORT="443"  # HTTPS port for docker.reactmotion.com

log_section "Nexus Registry Health Check"
echo "Timestamp: $(date)"
echo ""

# 1. Check if Nexus process is running
log_section "Nexus Process Status"
if pgrep -f nexus > /dev/null; then
    log_info "✓ Nexus process is running"
    echo "  PID(s): $(pgrep -f nexus)"
else
    log_error "✗ Nexus process is NOT running"
fi

# 2. Check Nexus service status
log_section "Nexus Service Status"
if systemctl is-active --quiet nexus 2>/dev/null; then
    log_info "✓ Nexus service is active"
    systemctl status nexus --no-pager | head -10
elif service nexus status > /dev/null 2>&1; then
    log_info "✓ Nexus service is running"
    service nexus status | head -10
else
    log_warning "⚠ Cannot determine Nexus service status"
fi

# 3. Check Nexus web interface
log_section "Nexus Web Interface"
if curl -sf -o /dev/null "$NEXUS_URL"; then
    log_info "✓ Nexus web interface is accessible at $NEXUS_URL"
else
    log_error "✗ Nexus web interface is NOT accessible at $NEXUS_URL"
fi

# 4. Check Nexus REST API
log_section "Nexus REST API"
if curl -sf -o /dev/null "$NEXUS_URL/service/rest/v1/status"; then
    log_info "✓ Nexus REST API is responding"
    echo "  Status: $(curl -s $NEXUS_URL/service/rest/v1/status)"
else
    log_error "✗ Nexus REST API is NOT responding"
fi

# 5. Check Docker Registry API
log_section "Docker Registry API"
if curl -sf -o /dev/null "http://localhost:$DOCKER_PORT/v2/"; then
    log_info "✓ Docker Registry API is accessible on port $DOCKER_PORT"
else
    log_error "✗ Docker Registry API is NOT accessible on port $DOCKER_PORT"
fi

# 6. Check NGINX reverse proxy (if applicable)
log_section "NGINX Reverse Proxy"
if systemctl is-active --quiet nginx 2>/dev/null; then
    log_info "✓ NGINX is active"
    
    # Check NGINX configuration
    if nginx -t 2>/dev/null; then
        log_info "✓ NGINX configuration is valid"
    else
        log_error "✗ NGINX configuration has errors"
        nginx -t 2>&1 | head -10
    fi
    
    # Check if NGINX is listening on HTTPS
    if netstat -tuln | grep -q ":${NGINX_PORT}"; then
        log_info "✓ NGINX is listening on port $NGINX_PORT"
    else
        log_warning "⚠ NGINX is not listening on port $NGINX_PORT"
    fi
else
    log_warning "⚠ NGINX is not running or not installed"
fi

# 7. Check disk space
log_section "Disk Space"
df -h | grep -E "^/dev/|^Filesystem"
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    log_error "✗ Disk usage is critical: ${DISK_USAGE}%"
elif [ "$DISK_USAGE" -gt 80 ]; then
    log_warning "⚠ Disk usage is high: ${DISK_USAGE}%"
else
    log_info "✓ Disk usage is acceptable: ${DISK_USAGE}%"
fi

# 8. Check memory
log_section "Memory Usage"
free -h
MEM_USAGE=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
if [ "$MEM_USAGE" -gt 90 ]; then
    log_error "✗ Memory usage is critical: ${MEM_USAGE}%"
elif [ "$MEM_USAGE" -gt 80 ]; then
    log_warning "⚠ Memory usage is high: ${MEM_USAGE}%"
else
    log_info "✓ Memory usage is acceptable: ${MEM_USAGE}%"
fi

# 9. Check Nexus logs for errors
log_section "Recent Nexus Errors"
NEXUS_LOG="/opt/nexus/sonatype-work/nexus3/log/nexus.log"
if [ -f "$NEXUS_LOG" ]; then
    echo "Last 10 error entries:"
    grep -i error "$NEXUS_LOG" | tail -10 || echo "  No recent errors found"
else
    log_warning "⚠ Nexus log file not found at $NEXUS_LOG"
fi

# 10. Check port bindings
log_section "Port Bindings"
echo "Nexus-related ports:"
netstat -tuln | grep -E ":(8081|$DOCKER_PORT|$NGINX_PORT)" || echo "  No ports found"

# 11. Test Docker Registry authentication
log_section "Docker Registry Authentication Test"
REGISTRY_USER="coolify-system"
REGISTRY_PASS='9sFPGGDJUFnE4z*z4Aj9'

if curl -sf -u "$REGISTRY_USER:$REGISTRY_PASS" "http://localhost:$DOCKER_PORT/v2/" > /dev/null 2>&1; then
    log_info "✓ Local Docker registry authentication successful"
else
    log_error "✗ Local Docker registry authentication failed"
    
    # Get detailed error
    response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -u "$REGISTRY_USER:$REGISTRY_PASS" "http://localhost:$DOCKER_PORT/v2/" 2>&1)
    http_code=$(echo "$response" | grep HTTP_CODE | cut -d: -f2)
    echo "  HTTP Response Code: $http_code"
fi

# 12. Check external accessibility
log_section "External Accessibility"
if curl -sf "https://docker.reactmotion.com/v2/" > /dev/null 2>&1; then
    log_info "✓ Registry is externally accessible via HTTPS"
else
    log_warning "⚠ Registry may not be externally accessible (auth may be required)"
fi

# Summary
echo ""
log_section "DIAGNOSIS SUMMARY"

if pgrep -f nexus > /dev/null && curl -sf -o /dev/null "$NEXUS_URL"; then
    log_info "Nexus appears to be running locally"
else
    log_error "Nexus has issues and needs attention"
fi

if [ "$DISK_USAGE" -gt 90 ] || [ "$MEM_USAGE" -gt 90 ]; then
    log_error "Resource constraints detected - this may cause service issues"
fi

echo ""
log_section "RECOMMENDED ACTIONS"

if ! pgrep -f nexus > /dev/null; then
    echo "1. Start Nexus service:"
    echo "   sudo systemctl start nexus"
    echo "   OR"
    echo "   sudo service nexus start"
fi

if [ "$DISK_USAGE" -gt 80 ]; then
    echo "2. Free up disk space:"
    echo "   - Clean up old Docker images: docker system prune -a"
    echo "   - Clean up Nexus blob store"
    echo "   - Check Nexus cleanup policies"
fi

if [ "$MEM_USAGE" -gt 80 ]; then
    echo "3. Address memory usage:"
    echo "   - Restart Nexus service"
    echo "   - Check for memory leaks"
    echo "   - Consider increasing server RAM"
fi

if ! systemctl is-active --quiet nginx 2>/dev/null; then
    echo "4. Start NGINX if needed:"
    echo "   sudo systemctl start nginx"
fi

echo ""
echo "For full Nexus restart:"
echo "  sudo systemctl restart nexus"
echo "  sudo systemctl restart nginx"
echo ""
echo "To view Nexus logs:"
echo "  sudo tail -f /opt/nexus/sonatype-work/nexus3/log/nexus.log"