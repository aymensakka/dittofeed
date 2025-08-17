#!/bin/bash

# ==============================================================================
# Quick Local Deployment Test Script
# Uses existing Docker images to test multi-tenant setup locally
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# Check if images exist
check_images() {
    print_header "Checking Docker Images"
    
    IMAGES_EXIST=true
    
    # Check for production images
    if docker images | grep -q "aymenbs/dittofeed-api"; then
        print_success "API image found: aymenbs/dittofeed-api"
    else
        print_error "API image not found"
        IMAGES_EXIST=false
    fi
    
    if docker images | grep -q "aymenbs/dittofeed-dashboard"; then
        print_success "Dashboard image found: aymenbs/dittofeed-dashboard"
    else
        print_error "Dashboard image not found"
        IMAGES_EXIST=false
    fi
    
    if [[ "$IMAGES_EXIST" == false ]]; then
        print_info "Pulling images from Docker Hub..."
        docker pull aymenbs/dittofeed-api:multitenant-redis
        docker pull aymenbs/dittofeed-dashboard:multitenant-redis
        docker pull aymenbs/dittofeed-worker:multitenant-redis
    fi
}

# Create minimal docker-compose
create_docker_compose() {
    print_header "Creating Docker Compose Configuration"
    
    cat > "$PROJECT_ROOT/docker-compose.test-local.yaml" <<'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: dittofeed_local_postgres
    environment:
      POSTGRES_DB: dittofeed
      POSTGRES_USER: dittofeed
      POSTGRES_PASSWORD: testpass123
    ports:
      - "5434:5432"
    volumes:
      - ./deployment/init-database.sql:/docker-entrypoint-initdb.d/01-init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dittofeed -d dittofeed"]
      interval: 5s
      timeout: 5s
      retries: 10

  redis:
    image: redis:7-alpine
    container_name: dittofeed_local_redis
    command: redis-server --requirepass testpass123
    ports:
      - "6381:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "testpass123", "ping"]
      interval: 5s
      timeout: 5s
      retries: 10

  api:
    image: aymenbs/dittofeed-api:multitenant-redis
    container_name: dittofeed_local_api
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      NODE_ENV: production
      PORT: 3001
      AUTH_MODE: multi-tenant
      MULTITENANCY_ENABLED: "true"
      WORKSPACE_ISOLATION_ENABLED: "true"
      DATABASE_URL: postgresql://dittofeed:testpass123@postgres:5432/dittofeed
      REDIS_URL: redis://:testpass123@redis:6379
      JWT_SECRET: test-jwt-secret-32-chars-minimum-ok
      ENCRYPTION_KEY: test-encryption-key-32-chars-min
      SECRET_KEY: test-secret-key-32-chars-minimum
      BOOTSTRAP: "true"
      BOOTSTRAP_SAFE: "true"
      BOOTSTRAP_WORKSPACE_NAME: TestWorkspace
      BOOTSTRAP_WORKSPACE_ADMIN_EMAIL: admin@test.local
      API_BASE_URL: http://localhost:3001
      CORS_ORIGIN: http://localhost:3002
      CLICKHOUSE_HOST: http://localhost:8123
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: ""
      CLICKHOUSE_DATABASE: dittofeed
    ports:
      - "3001:3001"
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3001/api"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

  dashboard:
    image: aymenbs/dittofeed-dashboard:multitenant-redis
    container_name: dittofeed_local_dashboard
    depends_on:
      api:
        condition: service_healthy
    environment:
      NODE_ENV: production
      AUTH_MODE: multi-tenant
      NEXTAUTH_SECRET: test-nextauth-secret-for-testing
      NEXTAUTH_URL: http://localhost:3002
      API_BASE_URL: http://api:3001
      NEXT_PUBLIC_API_BASE_URL: http://localhost:3001
      GOOGLE_CLIENT_ID: test-client-id
      GOOGLE_CLIENT_SECRET: test-client-secret
    ports:
      - "3002:3000"
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3000"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

networks:
  default:
    name: dittofeed_local_test
EOF
    
    print_success "Docker Compose configuration created"
}

# Create database init script
create_db_init() {
    print_header "Creating Database Init Script"
    
    # Extract schema from the codebase if available
    if [[ -f "$PROJECT_ROOT/packages/backend-lib/drizzle/0000_init.sql" ]]; then
        cp "$PROJECT_ROOT/packages/backend-lib/drizzle/0000_init.sql" "$PROJECT_ROOT/deployment/init-database.sql"
        print_success "Using existing migration file"
    else
        print_info "Creating basic schema..."
        cat > "$PROJECT_ROOT/deployment/init-database.sql" <<'EOF'
-- Basic Dittofeed Multi-tenant Schema
-- This is a minimal schema for testing

-- Create necessary enums
CREATE TYPE workspace_type AS ENUM ('Root', 'Child', 'Parent');
CREATE TYPE resource_type AS ENUM ('Workspace', 'UserProperty', 'Segment', 'Journey');
CREATE TYPE channel_type AS ENUM ('Email', 'Sms', 'Push', 'Webhook');

-- Create workspaces table
CREATE TABLE IF NOT EXISTS workspaces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    type workspace_type NOT NULL DEFAULT 'Root',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create workspace_members table
CREATE TABLE IF NOT EXISTS workspace_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id),
    email VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'Admin',
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(workspace_id, email)
);

-- Create api_keys table
CREATE TABLE IF NOT EXISTS api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id),
    name VARCHAR(255) NOT NULL,
    key_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create write_keys table
CREATE TABLE IF NOT EXISTS write_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id),
    name VARCHAR(255) NOT NULL,
    write_key VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Insert default workspace
INSERT INTO workspaces (id, name, type) 
VALUES ('00000000-0000-0000-0000-000000000000', 'Default', 'Root')
ON CONFLICT DO NOTHING;
EOF
    fi
    
    print_success "Database init script created"
}

# Start services
start_services() {
    print_header "Starting Services"
    
    cd "$PROJECT_ROOT"
    
    # Stop any existing containers
    docker-compose -f docker-compose.test-local.yaml down 2>/dev/null || true
    
    # Start services
    print_info "Starting services..."
    docker-compose -f docker-compose.test-local.yaml up -d
    
    # Wait for services
    print_info "Waiting for services to be ready..."
    sleep 15
    
    # Show status
    docker-compose -f docker-compose.test-local.yaml ps
}

# Test endpoints
test_endpoints() {
    print_header "Testing Endpoints"
    
    # Test API
    print_info "Testing API..."
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/api 2>/dev/null || echo "000")
    if [[ "$response" == "200" ]] || [[ "$response" == "404" ]]; then
        print_success "API responding: HTTP $response"
    else
        print_error "API not responding: HTTP $response"
    fi
    
    # Test Dashboard
    print_info "Testing Dashboard..."
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3002 2>/dev/null || echo "000")
    if [[ "$response" == "200" ]] || [[ "$response" == "307" ]]; then
        print_success "Dashboard responding: HTTP $response"
    else
        print_error "Dashboard not responding: HTTP $response"
    fi
    
    # Check database
    print_info "Checking database..."
    docker exec dittofeed_local_postgres psql -U dittofeed -d dittofeed -c "\\dt" 2>/dev/null && \
        print_success "Database accessible" || \
        print_error "Database not accessible"
}

# Show logs
show_logs() {
    print_header "Recent Logs"
    
    echo -e "\n${BLUE}API Logs:${NC}"
    docker logs dittofeed_local_api --tail 10 2>&1
    
    echo -e "\n${BLUE}Dashboard Logs:${NC}"
    docker logs dittofeed_local_dashboard --tail 10 2>&1
}

# Main execution
main() {
    print_header "Local Multi-Tenant Deployment Test"
    
    case "${1:-}" in
        stop)
            print_info "Stopping services..."
            docker-compose -f "$PROJECT_ROOT/docker-compose.test-local.yaml" down
            print_success "Services stopped"
            exit 0
            ;;
        clean)
            print_info "Cleaning up..."
            docker-compose -f "$PROJECT_ROOT/docker-compose.test-local.yaml" down -v
            rm -f "$PROJECT_ROOT/docker-compose.test-local.yaml"
            rm -f "$PROJECT_ROOT/deployment/init-database.sql"
            print_success "Cleanup completed"
            exit 0
            ;;
        logs)
            docker-compose -f "$PROJECT_ROOT/docker-compose.test-local.yaml" logs -f
            exit 0
            ;;
    esac
    
    check_images
    create_db_init
    create_docker_compose
    start_services
    test_endpoints
    show_logs
    
    print_header "Deployment Complete"
    print_success "Local deployment is running!"
    echo ""
    echo "Access Points:"
    echo "  API:       http://localhost:3001"
    echo "  Dashboard: http://localhost:3002"
    echo "  Database:  postgresql://dittofeed:testpass123@localhost:5434/dittofeed"
    echo "  Redis:     redis://:testpass123@localhost:6381"
    echo ""
    echo "Commands:"
    echo "  View logs:  $0 logs"
    echo "  Stop:       $0 stop"
    echo "  Clean:      $0 clean"
    echo ""
    echo "Test deployment with:"
    echo "  curl http://localhost:3001/api"
    echo "  curl http://localhost:3002"
}

main "$@"