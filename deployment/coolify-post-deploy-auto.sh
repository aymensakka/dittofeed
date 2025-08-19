#!/bin/bash

# ==============================================================================
# Coolify Post-Deploy Script - Auto-configure after deployment
# This script runs after Coolify deploys/restarts containers to:
# 1. Update Cloudflare tunnel with new IPs
# 2. Ensure workspace exists
# 3. Fix any network configuration issues
# ==============================================================================

set -e

echo "====================================================="
echo "Coolify Post-Deploy Auto-Configuration"
echo "Started at: $(date)"
echo "====================================================="
echo ""

# Configuration
PROJECT_ID="${PROJECT_ID:-p0gcsc088cogco0cokco4404}"
WORKSPACE_NAME="${BOOTSTRAP_WORKSPACE_NAME:-caramel}"
WORKSPACE_DOMAIN="${DOMAIN:-caramelme.com}"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Find containers
find_containers() {
    API_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "api.*${PROJECT_ID}" | head -1)
    POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
    DASHBOARD_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "dashboard.*${PROJECT_ID}" | head -1)
    CLOUDFLARED_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E "cloudflared.*${PROJECT_ID}" | head -1)
}

# Get container IPs
get_container_ips() {
    [ ! -z "$API_CONTAINER" ] && API_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $API_CONTAINER 2>/dev/null | head -c -1)
    [ ! -z "$DASHBOARD_CONTAINER" ] && DASHBOARD_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DASHBOARD_CONTAINER 2>/dev/null | head -c -1)
}

# Wait for containers to be ready
wait_for_containers() {
    log "Waiting for containers to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        find_containers
        if [ ! -z "$API_CONTAINER" ] && [ ! -z "$DASHBOARD_CONTAINER" ] && [ ! -z "$POSTGRES_CONTAINER" ]; then
            log "✅ All critical containers found"
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log "⚠️  Not all containers ready after ${max_attempts} attempts"
    return 1
}

# Update Cloudflare tunnel
update_cloudflare_tunnel() {
    if [ -z "$CLOUDFLARED_CONTAINER" ]; then
        log "⚠️  Cloudflared container not found, skipping tunnel update"
        return 1
    fi
    
    if [ -z "$API_IP" ] || [ -z "$DASHBOARD_IP" ]; then
        log "⚠️  Container IPs not available, skipping tunnel update"
        return 1
    fi
    
    log "Updating Cloudflare tunnel configuration..."
    
    # Generate config
    cat > /tmp/cloudflared-config.yml << EOF
tunnel: auto
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: communication-api.${WORKSPACE_DOMAIN}
    service: http://${API_IP}:3001
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      
  - hostname: communication-dashboard.${WORKSPACE_DOMAIN}
    service: http://${DASHBOARD_IP}:3000
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      
  - service: http_status:404
EOF
    
    # Update container config
    if docker cp /tmp/cloudflared-config.yml ${CLOUDFLARED_CONTAINER}:/etc/cloudflared/config.yml 2>/dev/null; then
        docker restart ${CLOUDFLARED_CONTAINER} > /dev/null 2>&1
        log "✅ Cloudflare tunnel updated with new IPs"
        log "   API: http://${API_IP}:3001"
        log "   Dashboard: http://${DASHBOARD_IP}:3000"
        return 0
    else
        log "❌ Failed to update Cloudflare config"
        return 1
    fi
}

# Ensure workspace exists
ensure_workspace() {
    if [ -z "$POSTGRES_CONTAINER" ]; then
        log "⚠️  PostgreSQL container not found, skipping workspace check"
        return 1
    fi
    
    # Check if workspace exists
    WORKSPACE_COUNT=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c "SELECT COUNT(*) FROM \"Workspace\" WHERE name = '${WORKSPACE_NAME}';" 2>/dev/null || echo "0")
    WORKSPACE_COUNT=$(echo $WORKSPACE_COUNT | tr -d ' ')
    
    if [ "$WORKSPACE_COUNT" = "0" ]; then
        log "Creating workspace '${WORKSPACE_NAME}'..."
        
        # Create workspace
        WORKSPACE_ID=$(uuidgen 2>/dev/null || echo "ws-$(date +%s)")
        docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "
        INSERT INTO \"Workspace\" (id, name, type, status, domain, \"createdAt\", \"updatedAt\")
        VALUES ('$WORKSPACE_ID', '${WORKSPACE_NAME}', 'Root', 'Active', '${WORKSPACE_DOMAIN}', NOW(), NOW())
        ON CONFLICT (name) DO UPDATE SET domain = '${WORKSPACE_DOMAIN}', \"updatedAt\" = NOW();
        " 2>/dev/null && log "✅ Workspace created/updated" || log "❌ Failed to create workspace"
    else
        log "✅ Workspace '${WORKSPACE_NAME}' already exists"
        
        # Ensure domain is correct
        docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "
        UPDATE \"Workspace\" SET domain = '${WORKSPACE_DOMAIN}' WHERE name = '${WORKSPACE_NAME}';
        " 2>/dev/null
    fi
}

# Health check
check_health() {
    log "Performing health checks..."
    
    # Check API
    if [ ! -z "$API_CONTAINER" ]; then
        API_STATUS=$(docker inspect -f '{{.State.Health.Status}}' $API_CONTAINER 2>/dev/null || echo "unknown")
        log "API health: $API_STATUS"
    fi
    
    # Check Dashboard
    if [ ! -z "$DASHBOARD_CONTAINER" ]; then
        DASHBOARD_STATUS=$(docker inspect -f '{{.State.Health.Status}}' $DASHBOARD_CONTAINER 2>/dev/null || echo "unknown")
        log "Dashboard health: $DASHBOARD_STATUS"
    fi
}

# Main execution
main() {
    log "Starting post-deploy configuration..."
    
    # Wait for containers
    if ! wait_for_containers; then
        log "❌ Containers not ready, exiting"
        exit 1
    fi
    
    # Get IPs
    get_container_ips
    
    # Update Cloudflare
    update_cloudflare_tunnel
    
    # Ensure workspace
    ensure_workspace
    
    # Health check
    check_health
    
    # Save state
    cat > /tmp/post-deploy-state.txt << EOF
Post-Deploy State - $(date)
========================================
API Container: $API_CONTAINER
API IP: ${API_IP}:3001
Dashboard Container: $DASHBOARD_CONTAINER
Dashboard IP: ${DASHBOARD_IP}:3000
Workspace: ${WORKSPACE_NAME}
Domain: ${WORKSPACE_DOMAIN}
========================================
EOF
    
    log "✅ Post-deploy configuration completed"
    log "State saved to: /tmp/post-deploy-state.txt"
    
    # Final URLs
    echo ""
    echo "====================================================="
    echo "Access URLs:"
    echo "  API: https://communication-api.${WORKSPACE_DOMAIN}"
    echo "  Dashboard: https://communication-dashboard.${WORKSPACE_DOMAIN}"
    echo "====================================================="
}

# Run main function
main "$@"