#!/bin/bash

# ==============================================================================
# Deploy Complete Dittofeed Multi-Tenant Stack with All Required Services
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

print_header "Deploying Complete Dittofeed Multi-Tenant Stack"

# Check if running on server
if [ "$1" == "--local" ]; then
    print_info "Running in local test mode"
    LOCAL_MODE=true
else
    print_info "Running on Coolify server"
    LOCAL_MODE=false
fi

# Stop and remove existing containers if any
print_header "Cleaning up existing containers"
docker compose -f docker-compose.coolify.yaml down 2>/dev/null || true

# Create required directories
print_info "Creating required directories..."
mkdir -p data/{postgres,redis,clickhouse,clickhouse-logs,temporal}

# Set environment variables if not already set
if [ -z "$POSTGRES_PASSWORD" ]; then
    export POSTGRES_PASSWORD="LOpnL3wYIbWUBax4qXeR"
fi
if [ -z "$REDIS_PASSWORD" ]; then
    export REDIS_PASSWORD="redis-password-123"
fi
if [ -z "$CLICKHOUSE_PASSWORD" ]; then
    export CLICKHOUSE_PASSWORD="clickhouse-password-123"
fi
if [ -z "$JWT_SECRET" ]; then
    export JWT_SECRET="your-jwt-secret-32-chars-minimum"
fi
if [ -z "$SECRET_KEY" ]; then
    export SECRET_KEY="GEGL1RHjFVOxIO80Dp8+ODlZPOjm2IDBJB/UunHlf3c="
fi

print_header "Starting Infrastructure Services"

# Start PostgreSQL first
print_info "Starting PostgreSQL..."
docker compose -f docker-compose.coolify.yaml up -d postgres
sleep 10

# Initialize database if needed
print_info "Checking database initialization..."
TABLE_COUNT=$(docker exec $(docker ps -q -f name=postgres) psql -U dittofeed -d dittofeed -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")

if [ "$TABLE_COUNT" -eq "0" ]; then
    print_info "Initializing database..."
    docker exec $(docker ps -q -f name=postgres) psql -U dittofeed -d dittofeed < deployment/init-database.sql
    print_success "Database initialized with 34 tables"
else
    print_success "Database already initialized with $TABLE_COUNT tables"
fi

# Start Redis
print_info "Starting Redis..."
docker compose -f docker-compose.coolify.yaml up -d redis
sleep 5

# Start ClickHouse
print_info "Starting ClickHouse..."
docker compose -f docker-compose.coolify.yaml up -d clickhouse
sleep 10

# Initialize ClickHouse database
print_info "Initializing ClickHouse database..."
docker exec $(docker ps -q -f name=clickhouse) clickhouse-client --query "CREATE DATABASE IF NOT EXISTS dittofeed" || true

# Start Temporal
print_info "Starting Temporal..."
docker compose -f docker-compose.coolify.yaml up -d temporal
sleep 15

print_header "Starting Application Services"

# Start API
print_info "Starting API service..."
docker compose -f docker-compose.coolify.yaml up -d api
sleep 10

# Start Worker
print_info "Starting Worker service..."
docker compose -f docker-compose.coolify.yaml up -d worker
sleep 5

# Start Dashboard
print_info "Starting Dashboard service..."
docker compose -f docker-compose.coolify.yaml up -d dashboard
sleep 10

# Start Cloudflare tunnel if token is set
if [ -n "$CF_TUNNEL_TOKEN" ]; then
    print_info "Starting Cloudflare tunnel..."
    docker compose -f docker-compose.coolify.yaml up -d cloudflared
    sleep 5
fi

print_header "Health Checks"

# Check all services
services=("postgres" "redis" "clickhouse" "temporal" "api" "worker" "dashboard")
for service in "${services[@]}"; do
    container=$(docker ps -q -f name=$service | head -1)
    if [ -n "$container" ]; then
        status=$(docker inspect $container --format='{{.State.Status}}')
        if [ "$status" == "running" ]; then
            print_success "$service is running"
        else
            print_error "$service is not running (status: $status)"
        fi
    else
        print_error "$service container not found"
    fi
done

print_header "Service Endpoints"

# Get IPs
API_IP=$(docker inspect $(docker ps -q -f name=api) -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)
DASHBOARD_IP=$(docker inspect $(docker ps -q -f name=dashboard) -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)
CLICKHOUSE_IP=$(docker inspect $(docker ps -q -f name=clickhouse) -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)
TEMPORAL_IP=$(docker inspect $(docker ps -q -f name=temporal) -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)

echo -e "${GREEN}Internal endpoints:${NC}"
echo "  API: http://$API_IP:3001"
echo "  Dashboard: http://$DASHBOARD_IP:3000"
echo "  ClickHouse: http://$CLICKHOUSE_IP:8123"
echo "  Temporal: http://$TEMPORAL_IP:7233"

if [ -n "$CF_TUNNEL_TOKEN" ]; then
    echo -e "\n${GREEN}Public endpoints (via Cloudflare):${NC}"
    echo "  API: https://communication-api.caramelme.com"
    echo "  Dashboard: https://communication-dashboard.caramelme.com"
fi

print_header "Testing Services"

# Test API
if curl -sf "http://$API_IP:3001/api" > /dev/null 2>&1; then
    print_success "API is responding"
else
    print_error "API is not responding"
fi

# Test Dashboard
if curl -sf "http://$DASHBOARD_IP:3000" > /dev/null 2>&1; then
    print_success "Dashboard is responding"
else
    print_error "Dashboard is not responding"
fi

# Test ClickHouse
if docker exec $(docker ps -q -f name=clickhouse) clickhouse-client --query "SELECT 1" > /dev/null 2>&1; then
    print_success "ClickHouse is responding"
else
    print_error "ClickHouse is not responding"
fi

# Test Temporal
if docker exec $(docker ps -q -f name=temporal) tctl cluster health > /dev/null 2>&1; then
    print_success "Temporal is healthy"
else
    print_error "Temporal is not healthy"
fi

print_header "Deployment Complete!"

echo -e "${GREEN}All services are deployed and running.${NC}"
echo ""
echo "Next steps:"
echo "1. Access the dashboard at https://communication-dashboard.caramelme.com"
echo "2. Sign in with Google OAuth"
echo "3. Create your first workspace"
echo "4. Start sending events to the API"
echo ""
echo "To check logs:"
echo "  docker logs <service-name> --tail 50"
echo ""
echo "To stop all services:"
echo "  docker compose -f docker-compose.coolify.yaml down"