#!/bin/bash

# Dittofeed Enterprise Multitenancy Production Deployment Script
# This script automates the deployment process with Cloudflare Zero Trust

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="production"
COMPOSE_FILE="docker-compose.prod.yaml"
ENV_FILE=".env.prod"
BACKUP_DIR="./backups"
LOG_FILE="deploy.log"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Wait for service to be healthy
wait_for_service() {
    local service_name="$1"
    local max_attempts=30
    local attempt=0
    
    log "Waiting for $service_name to be healthy..."
    
    while [ $attempt -lt $max_attempts ]; do
        if docker-compose -f "$COMPOSE_FILE" ps "$service_name" | grep -q "healthy\|Up"; then
            log "$service_name is healthy"
            return 0
        fi
        
        attempt=$((attempt + 1))
        sleep 10
        echo -n "."
    done
    
    error "$service_name failed to become healthy after $((max_attempts * 10)) seconds"
}

# =============================================================================
# PREFLIGHT CHECKS
# =============================================================================

preflight_checks() {
    log "Running preflight checks..."
    
    # Check required commands
    for cmd in docker docker-compose curl; do
        if ! command_exists "$cmd"; then
            error "$cmd is not installed. Please install it first."
        fi
    done
    
    # Check Docker is running
    if ! docker info >/dev/null 2>&1; then
        error "Docker is not running. Please start Docker first."
    fi
    
    # Check if files exist
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        error "Docker Compose file $COMPOSE_FILE not found"
    fi
    
    if [[ ! -f "$ENV_FILE" ]]; then
        error "Environment file $ENV_FILE not found"
    fi
    
    # Check environment variables
    if ! grep -q "POSTGRES_PASSWORD=" "$ENV_FILE" || grep -q "your_secure_postgres_password_here" "$ENV_FILE"; then
        error "Please set POSTGRES_PASSWORD in $ENV_FILE"
    fi
    
    if ! grep -q "JWT_SECRET=" "$ENV_FILE" || grep -q "your_jwt_secret_32_chars_min_here" "$ENV_FILE"; then
        error "Please set JWT_SECRET in $ENV_FILE"
    fi
    
    if ! grep -q "CF_TUNNEL_TOKEN=" "$ENV_FILE" || grep -q "your-cloudflare-tunnel-token-here" "$ENV_FILE"; then
        warn "CF_TUNNEL_TOKEN not set in $ENV_FILE. Cloudflare Tunnel will not work."
    fi
    
    # Check available disk space (minimum 10GB)
    available_space=$(df . | awk 'NR==2 {print $4}')
    min_space=10485760  # 10GB in KB
    
    if [[ $available_space -lt $min_space ]]; then
        error "Insufficient disk space. At least 10GB required, only $(($available_space / 1024 / 1024))GB available."
    fi
    
    # Check available memory (minimum 4GB)
    available_memory=$(free -m | awk 'NR==2{print $7}')
    min_memory=4096  # 4GB in MB
    
    if [[ $available_memory -lt $min_memory ]]; then
        warn "Low available memory. At least 4GB recommended, only ${available_memory}MB available."
    fi
    
    log "Preflight checks completed successfully"
}

# =============================================================================
# BACKUP FUNCTIONS
# =============================================================================

create_backup() {
    if [[ "$1" == "--skip-backup" ]]; then
        log "Skipping backup as requested"
        return 0
    fi
    
    log "Creating backup before deployment..."
    
    mkdir -p "$BACKUP_DIR"
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/dittofeed_backup_$backup_timestamp.sql"
    
    # Check if PostgreSQL is running
    if docker-compose -f "$COMPOSE_FILE" ps postgres | grep -q "Up"; then
        log "Creating database backup..."
        docker-compose -f "$COMPOSE_FILE" exec -T postgres pg_dump -U dittofeed dittofeed > "$backup_file"
        
        if [[ -f "$backup_file" ]] && [[ -s "$backup_file" ]]; then
            log "Database backup created: $backup_file"
        else
            warn "Database backup may have failed or is empty"
        fi
    else
        log "PostgreSQL not running, skipping database backup"
    fi
    
    # Backup configuration files
    local config_backup="$BACKUP_DIR/config_backup_$backup_timestamp.tar.gz"
    tar -czf "$config_backup" config/ .env.prod docker-compose.prod.yaml 2>/dev/null || true
    
    if [[ -f "$config_backup" ]]; then
        log "Configuration backup created: $config_backup"
    fi
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================

pull_images() {
    log "Pulling latest Docker images..."
    docker-compose -f "$COMPOSE_FILE" pull
}

start_infrastructure() {
    log "Starting infrastructure services..."
    
    # Start database first
    docker-compose -f "$COMPOSE_FILE" up -d postgres redis
    
    # Wait for database to be ready
    wait_for_service postgres
    wait_for_service redis
    
    log "Infrastructure services started successfully"
}

run_migrations() {
    log "Running database migrations..."
    
    # Check if migration container/command exists
    if docker-compose -f "$COMPOSE_FILE" run --rm api npm run db:migrate 2>/dev/null; then
        log "Database migrations completed successfully"
    else
        warn "Migration command not found or failed. Please run migrations manually."
    fi
}

start_application() {
    log "Starting application services..."
    
    # Start application services
    docker-compose -f "$COMPOSE_FILE" up -d api dashboard worker
    
    # Wait for services to be ready
    wait_for_service api
    wait_for_service dashboard
    wait_for_service worker
    
    log "Application services started successfully"
}

start_monitoring() {
    log "Starting monitoring services..."
    
    # Start monitoring stack
    docker-compose -f "$COMPOSE_FILE" up -d prometheus grafana
    
    # Wait for services to be ready
    wait_for_service prometheus
    wait_for_service grafana
    
    log "Monitoring services started successfully"
}

start_tunnel() {
    log "Starting Cloudflare Tunnel..."
    
    # Start Cloudflare tunnel
    docker-compose -f "$COMPOSE_FILE" up -d cloudflared
    
    # Give tunnel time to establish connection
    sleep 30
    
    if docker-compose -f "$COMPOSE_FILE" ps cloudflared | grep -q "Up"; then
        log "Cloudflare Tunnel started successfully"
    else
        warn "Cloudflare Tunnel may not be working. Check CF_TUNNEL_TOKEN configuration."
    fi
}

# =============================================================================
# HEALTH CHECK FUNCTIONS
# =============================================================================

health_check() {
    log "Running health checks..."
    
    local failed_checks=0
    
    # Check API health
    info "Checking API health..."
    if curl -s -f http://localhost:3000/health >/dev/null 2>&1; then
        log "✓ API health check passed"
    else
        error "✗ API health check failed"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Check Dashboard
    info "Checking Dashboard..."
    if curl -s -f http://localhost:3001 >/dev/null 2>&1; then
        log "✓ Dashboard health check passed"
    else
        warn "✗ Dashboard health check failed"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Check Database connection
    info "Checking Database connection..."
    if docker-compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U dittofeed >/dev/null 2>&1; then
        log "✓ Database health check passed"
    else
        error "✗ Database health check failed"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Check Redis connection
    info "Checking Redis connection..."
    if docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli ping | grep -q PONG; then
        log "✓ Redis health check passed"
    else
        warn "✗ Redis health check failed"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Check Prometheus
    info "Checking Prometheus..."
    if curl -s -f http://localhost:9090/-/healthy >/dev/null 2>&1; then
        log "✓ Prometheus health check passed"
    else
        warn "✗ Prometheus health check failed"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Check Grafana
    info "Checking Grafana..."
    if curl -s -f http://localhost:3002/api/health >/dev/null 2>&1; then
        log "✓ Grafana health check passed"
    else
        warn "✗ Grafana health check failed"
        failed_checks=$((failed_checks + 1))
    fi
    
    if [[ $failed_checks -eq 0 ]]; then
        log "All health checks passed!"
    else
        warn "$failed_checks health checks failed. Please check the logs."
    fi
    
    return $failed_checks
}

# =============================================================================
# DEPLOYMENT STATUS
# =============================================================================

show_status() {
    log "Deployment Status:"
    echo ""
    
    # Show running services
    info "Running Services:"
    docker-compose -f "$COMPOSE_FILE" ps
    echo ""
    
    # Show URLs
    info "Access URLs:"
    echo "  Dashboard: https://app.your-domain.com (via Cloudflare)"
    echo "  API: https://api.your-domain.com (via Cloudflare)"
    echo "  Monitoring: https://monitoring.your-domain.com (via Cloudflare)"
    echo ""
    echo "  Local access (for debugging):"
    echo "  - API: http://localhost:3000"
    echo "  - Dashboard: http://localhost:3001"
    echo "  - Grafana: http://localhost:3002"
    echo "  - Prometheus: http://localhost:9090"
    echo ""
    
    # Show resource usage
    info "Resource Usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    echo ""
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

cleanup() {
    log "Cleaning up old containers and images..."
    
    # Remove stopped containers
    docker container prune -f
    
    # Remove unused images
    docker image prune -f
    
    # Remove unused volumes (be careful with this)
    # docker volume prune -f
    
    log "Cleanup completed"
}

# =============================================================================
# MAIN DEPLOYMENT FUNCTION
# =============================================================================

deploy() {
    local skip_backup="${1:-}"
    
    log "Starting Dittofeed Enterprise Multitenancy Deployment"
    log "Environment: $ENVIRONMENT"
    log "Compose file: $COMPOSE_FILE"
    log "Environment file: $ENV_FILE"
    echo ""
    
    # Run preflight checks
    preflight_checks
    
    # Create backup
    create_backup "$skip_backup"
    
    # Pull latest images
    pull_images
    
    # Start infrastructure
    start_infrastructure
    
    # Run migrations
    run_migrations
    
    # Start application
    start_application
    
    # Start monitoring
    start_monitoring
    
    # Start tunnel
    start_tunnel
    
    # Health checks
    health_check
    
    # Show status
    show_status
    
    log "Deployment completed successfully!"
    echo ""
    info "Next steps:"
    echo "1. Configure your Cloudflare Tunnel with the provided token"
    echo "2. Set up Cloudflare Zero Trust access policies"
    echo "3. Configure DNS records in Cloudflare"
    echo "4. Test access through your domain"
    echo "5. Set up monitoring alerts and backups"
}

# =============================================================================
# SCRIPT COMMANDS
# =============================================================================

case "${1:-deploy}" in
    "deploy")
        deploy "${2:-}"
        ;;
    "health")
        health_check
        ;;
    "status")
        show_status
        ;;
    "stop")
        log "Stopping all services..."
        docker-compose -f "$COMPOSE_FILE" down
        log "All services stopped"
        ;;
    "restart")
        log "Restarting all services..."
        docker-compose -f "$COMPOSE_FILE" restart
        log "All services restarted"
        ;;
    "logs")
        service="${2:-}"
        if [[ -n "$service" ]]; then
            docker-compose -f "$COMPOSE_FILE" logs -f "$service"
        else
            docker-compose -f "$COMPOSE_FILE" logs -f
        fi
        ;;
    "backup")
        create_backup
        ;;
    "cleanup")
        cleanup
        ;;
    "update")
        log "Updating Dittofeed..."
        pull_images
        docker-compose -f "$COMPOSE_FILE" up -d --force-recreate
        health_check
        log "Update completed"
        ;;
    "help"|"--help"|"-h")
        echo "Dittofeed Enterprise Deployment Script"
        echo ""
        echo "Usage: $0 [command] [options]"
        echo ""
        echo "Commands:"
        echo "  deploy [--skip-backup]  Deploy all services (default)"
        echo "  health                  Run health checks"
        echo "  status                  Show deployment status"
        echo "  stop                    Stop all services"
        echo "  restart                 Restart all services"
        echo "  logs [service]          Show logs (optionally for specific service)"
        echo "  backup                  Create manual backup"
        echo "  cleanup                 Clean up Docker resources"
        echo "  update                  Update to latest version"
        echo "  help                    Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 deploy              # Full deployment with backup"
        echo "  $0 deploy --skip-backup # Deploy without backup"
        echo "  $0 logs api            # Show API logs"
        echo "  $0 health              # Check service health"
        ;;
    *)
        error "Unknown command: $1. Use '$0 help' for usage information."
        ;;
esac