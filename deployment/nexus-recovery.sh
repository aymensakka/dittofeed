#!/bin/bash
# Nexus Registry Recovery Script
# Run this to recover Nexus when it's returning 503 errors

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

# Must run as root
if [ "$EUID" -ne 0 ]; then 
    log_error "Please run as root (use sudo)"
    exit 1
fi

log_section "Nexus Registry Recovery Process"
echo "This script will attempt to recover the Nexus Docker Registry"
echo ""

# 1. Stop services
log_section "Stopping Services"
log_info "Stopping Nexus service..."
systemctl stop nexus || service nexus stop || pkill -f nexus || true
sleep 5

log_info "Stopping NGINX..."
systemctl stop nginx || service nginx stop || true
sleep 2

# 2. Check and clean disk space
log_section "Checking Disk Space"
df -h
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

if [ "$DISK_USAGE" -gt 80 ]; then
    log_warning "Disk usage is high: ${DISK_USAGE}%"
    log_info "Cleaning up Docker resources..."
    
    # Clean Docker
    docker system prune -af --volumes || true
    
    # Clean package cache
    apt-get clean || yum clean all || true
    
    # Check again
    df -h
fi

# 3. Check memory
log_section "Checking Memory"
free -h

# Clear caches
log_info "Clearing system caches..."
sync
echo 3 > /proc/sys/vm/drop_caches

# 4. Check Nexus data directory
log_section "Checking Nexus Data Directory"
NEXUS_DATA="/opt/nexus/sonatype-work/nexus3"

if [ -d "$NEXUS_DATA" ]; then
    log_info "Nexus data directory exists"
    
    # Check for lock files
    if [ -f "$NEXUS_DATA/lock" ]; then
        log_warning "Found lock file, removing..."
        rm -f "$NEXUS_DATA/lock"
    fi
    
    # Check database
    if [ -d "$NEXUS_DATA/db" ]; then
        log_info "Database directory exists"
        du -sh "$NEXUS_DATA/db"
    fi
    
    # Check blob stores
    if [ -d "$NEXUS_DATA/blobs" ]; then
        log_info "Blob store directory exists"
        du -sh "$NEXUS_DATA/blobs"
    fi
else
    log_error "Nexus data directory not found at $NEXUS_DATA"
fi

# 5. Fix permissions
log_section "Fixing Permissions"
if [ -d "/opt/nexus" ]; then
    log_info "Setting correct permissions for Nexus..."
    chown -R nexus:nexus /opt/nexus || true
    chown -R nexus:nexus /opt/nexus/sonatype-work || true
fi

# 6. Check and fix NGINX configuration
log_section "Checking NGINX Configuration"
if [ -f "/etc/nginx/sites-enabled/docker.reactmotion.com" ]; then
    log_info "NGINX configuration found"
    
    # Test configuration
    if nginx -t; then
        log_info "✓ NGINX configuration is valid"
    else
        log_error "NGINX configuration has errors"
        nginx -t
    fi
else
    log_warning "NGINX configuration for docker.reactmotion.com not found"
fi

# 7. Increase system limits
log_section "Adjusting System Limits"
log_info "Setting higher limits for Nexus..."

# Update limits.conf
cat >> /etc/security/limits.conf << EOF
# Nexus limits
nexus soft nofile 65536
nexus hard nofile 65536
nexus soft nproc 4096
nexus hard nproc 4096
EOF

# Update systemd limits if using systemd
if [ -f "/etc/systemd/system/nexus.service" ]; then
    log_info "Updating systemd limits..."
    
    # Create override directory
    mkdir -p /etc/systemd/system/nexus.service.d
    
    # Create override file
    cat > /etc/systemd/system/nexus.service.d/override.conf << EOF
[Service]
LimitNOFILE=65536
LimitNPROC=4096
TimeoutStartSec=300
Restart=on-failure
RestartSec=10
EOF
    
    systemctl daemon-reload
fi

# 8. Start services
log_section "Starting Services"

log_info "Starting Nexus service..."
if systemctl start nexus; then
    log_info "✓ Nexus service started"
else
    log_error "Failed to start Nexus with systemctl, trying alternative..."
    service nexus start || /opt/nexus/bin/nexus start
fi

# Wait for Nexus to initialize
log_info "Waiting for Nexus to initialize (this may take 1-2 minutes)..."
for i in {1..60}; do
    if curl -sf -o /dev/null "http://localhost:8081"; then
        log_info "✓ Nexus is responding!"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Check if Nexus is up
if curl -sf -o /dev/null "http://localhost:8081"; then
    log_info "✓ Nexus web interface is accessible"
else
    log_error "Nexus is still not responding after 2 minutes"
    log_info "Checking logs..."
    tail -50 /opt/nexus/sonatype-work/nexus3/log/nexus.log
fi

log_info "Starting NGINX..."
if systemctl start nginx; then
    log_info "✓ NGINX started"
else
    service nginx start
fi

# 9. Verify recovery
log_section "Verifying Recovery"

# Test local access
if curl -sf -o /dev/null "http://localhost:8081"; then
    log_info "✓ Nexus web UI is accessible locally"
else
    log_error "✗ Nexus web UI is not accessible"
fi

# Test Docker registry
if curl -sf -o /dev/null "http://localhost:5000/v2/"; then
    log_info "✓ Docker registry API is accessible locally"
else
    log_error "✗ Docker registry API is not accessible"
fi

# Test external access
if curl -sf "https://docker.reactmotion.com/v2/" > /dev/null 2>&1; then
    log_info "✓ Registry is externally accessible"
else
    log_warning "⚠ Registry may not be externally accessible (auth required)"
fi

# 10. Show status
log_section "Current Status"
systemctl status nexus --no-pager | head -15
echo ""
systemctl status nginx --no-pager | head -10

log_section "Recovery Complete"
echo "Please test Docker registry access:"
echo "  docker login docker.reactmotion.com"
echo ""
echo "Monitor logs:"
echo "  tail -f /opt/nexus/sonatype-work/nexus3/log/nexus.log"
echo ""
echo "If issues persist, check:"
echo "  1. Firewall rules (port 443, 5000, 8081)"
echo "  2. SELinux/AppArmor policies"
echo "  3. Java heap memory settings in /opt/nexus/bin/nexus.vmoptions"