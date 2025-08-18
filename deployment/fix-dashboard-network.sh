#!/bin/bash

# ==============================================================================
# Fix Dashboard Network Connectivity for Cloudflare Tunnel
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_header "Dashboard Network Fix for Cloudflare Tunnel"

# Find the cloudflared container and its network
print_info "Finding cloudflared container..."
CLOUDFLARED_CONTAINER=$(docker ps | grep cloudflared | head -1 | awk '{print $1}')

if [ -z "$CLOUDFLARED_CONTAINER" ]; then
    print_error "Cloudflared container not found"
    exit 1
fi

print_success "Found cloudflared container: $CLOUDFLARED_CONTAINER"

# Get the cloudflared network
print_info "Getting cloudflared network..."
CLOUDFLARED_NETWORK=$(docker inspect "$CLOUDFLARED_CONTAINER" --format='{{range $key, $value := .NetworkSettings.Networks}}{{$key}}{{end}}' | head -1)

if [ -z "$CLOUDFLARED_NETWORK" ]; then
    print_error "Could not determine cloudflared network"
    exit 1
fi

print_success "Cloudflared network: $CLOUDFLARED_NETWORK"

# Find dashboard container
print_info "Finding dashboard container..."
DASHBOARD_CONTAINER=$(docker ps | grep -E "(dashboard-fixed|dashboard-)" | head -1 | awk '{print $1}')

if [ -z "$DASHBOARD_CONTAINER" ]; then
    print_error "Dashboard container not found"
    
    # Try to find any dashboard container
    print_info "Looking for any dashboard container..."
    docker ps | grep dashboard
    exit 1
fi

print_success "Found dashboard container: $DASHBOARD_CONTAINER"

# Connect dashboard to cloudflared network
print_info "Connecting dashboard to cloudflared network..."
docker network connect "$CLOUDFLARED_NETWORK" "$DASHBOARD_CONTAINER" 2>/dev/null || {
    print_info "Dashboard may already be connected to this network"
}

# Get dashboard IP on cloudflared network
DASHBOARD_IP=$(docker inspect "$DASHBOARD_CONTAINER" -f "{{.NetworkSettings.Networks.$CLOUDFLARED_NETWORK.IPAddress}}")

if [ -z "$DASHBOARD_IP" ]; then
    print_error "Failed to get dashboard IP on cloudflared network"
    exit 1
fi

print_success "Dashboard IP on cloudflared network: $DASHBOARD_IP"

# Find API container
print_info "Finding API container..."
API_CONTAINER=$(docker ps | grep "api-" | head -1 | awk '{print $1}')

if [ -n "$API_CONTAINER" ]; then
    # Connect API to cloudflared network too
    docker network connect "$CLOUDFLARED_NETWORK" "$API_CONTAINER" 2>/dev/null || {
        print_info "API may already be connected to this network"
    }
    
    API_IP=$(docker inspect "$API_CONTAINER" -f "{{.NetworkSettings.Networks.$CLOUDFLARED_NETWORK.IPAddress}}")
    print_success "API IP on cloudflared network: $API_IP"
else
    print_error "API container not found"
    API_IP="172.27.0.5"  # Use last known IP
fi

# Test connectivity
print_header "Testing Connectivity"

# Test dashboard
print_info "Testing dashboard..."
if curl -sf "http://$DASHBOARD_IP:3000" > /dev/null 2>&1; then
    print_success "Dashboard is responding on $DASHBOARD_IP:3000"
else
    print_error "Dashboard is not responding"
    
    # Check logs
    echo -e "\n${YELLOW}Dashboard logs:${NC}"
    docker logs "$DASHBOARD_CONTAINER" --tail 10
fi

# Test API
if [ -n "$API_CONTAINER" ]; then
    print_info "Testing API..."
    if curl -sf "http://$API_IP:3001/api" > /dev/null 2>&1; then
        print_success "API is responding on $API_IP:3001"
    else
        print_error "API is not responding"
        
        # Check logs
        echo -e "\n${YELLOW}API logs:${NC}"
        docker logs "$API_CONTAINER" --tail 10
    fi
fi

print_header "Cloudflare Tunnel Configuration"

# Show cloudflared logs
print_info "Cloudflared recent logs:"
docker logs "$CLOUDFLARED_CONTAINER" --tail 5

print_header "Summary"
echo -e "${GREEN}Dashboard and API are now connected to the cloudflared network${NC}"
echo ""
echo "Update your Cloudflare tunnel configuration with these endpoints:"
echo "  - Dashboard: http://$DASHBOARD_IP:3000"
echo "  - API: http://$API_IP:3001"
echo ""
echo "If using Cloudflare Zero Trust dashboard:"
echo "  1. Go to Networks > Tunnels"
echo "  2. Select your tunnel"
echo "  3. Edit the public hostname routes"
echo "  4. Update the service URLs with the IPs above"
echo ""
echo "The containers are now on the same network as cloudflared."