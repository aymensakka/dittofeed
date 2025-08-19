#!/bin/bash
# Check Docker Registry Status

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Registry details
REGISTRY="docker.reactmotion.com"
REGISTRY_USER="coolify-system"
REGISTRY_PASS='9sFPGGDJUFnE4z*z4Aj9'

log_info "Checking Docker Registry Status..."

# Check if registry is reachable
log_info "Testing network connectivity to $REGISTRY..."
if ping -c 3 $REGISTRY > /dev/null 2>&1; then
    log_info "✓ Registry host is reachable"
else
    log_error "✗ Cannot reach registry host"
fi

# Check HTTPS endpoint
log_info "Testing HTTPS endpoint..."
if curl -sf -o /dev/null "https://$REGISTRY/v2/" 2>/dev/null; then
    log_info "✓ HTTPS endpoint is responding"
else
    log_warning "⚠ HTTPS endpoint not responding (may require auth)"
fi

# Test authentication
log_info "Testing registry authentication..."
if curl -sf -u "$REGISTRY_USER:$REGISTRY_PASS" "https://$REGISTRY/v2/" > /dev/null 2>&1; then
    log_info "✓ Authentication successful"
else
    log_error "✗ Authentication failed or registry unavailable"
    
    # Get more details
    log_info "Getting detailed error..."
    response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -u "$REGISTRY_USER:$REGISTRY_PASS" "https://$REGISTRY/v2/" 2>&1)
    http_code=$(echo "$response" | grep HTTP_CODE | cut -d: -f2)
    
    if [ "$http_code" = "503" ]; then
        log_error "Registry is returning 503 Service Unavailable"
        log_error "The Nexus registry server appears to be down or under maintenance"
    elif [ "$http_code" = "401" ]; then
        log_error "Authentication failed (401 Unauthorized)"
    else
        log_error "Registry returned HTTP code: $http_code"
    fi
fi

# Check Docker login
log_info "Testing Docker CLI login..."
if echo "$REGISTRY_PASS" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin > /dev/null 2>&1; then
    log_info "✓ Docker login successful"
    docker logout "$REGISTRY" > /dev/null 2>&1
else
    log_error "✗ Docker login failed"
fi

log_info "Registry check complete!"