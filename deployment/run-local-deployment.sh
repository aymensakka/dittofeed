#!/bin/bash

# ==============================================================================
# Run Dittofeed Locally with Docker Compose
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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.local-dev.yaml"

# Create docker-compose file
create_compose_file() {
    print_header "Creating Docker Compose Configuration"
    
    cat > "$COMPOSE_FILE" <<'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: dittofeed_postgres
    environment:
      POSTGRES_DB: dittofeed
      POSTGRES_USER: dittofeed
      POSTGRES_PASSWORD: localpass
    ports:
      - "5433:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dittofeed -d dittofeed"]
      interval: 5s
      timeout: 5s
      retries: 10

  redis:
    image: redis:7-alpine
    container_name: dittofeed_redis
    command: redis-server --requirepass localpass
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "localpass", "ping"]
      interval: 5s
      timeout: 5s
      retries: 10

  api:
    image: dittofeed-api:local
    container_name: dittofeed_api
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
      DATABASE_URL: postgresql://dittofeed:localpass@postgres:5432/dittofeed
      DATABASE_DIRECT_URL: postgresql://dittofeed:localpass@postgres:5432/dittofeed
      REDIS_URL: redis://:localpass@redis:6379
      JWT_SECRET: local-jwt-secret-32-characters-min
      ENCRYPTION_KEY: local-encryption-key-32-chars-ok
      SECRET_KEY: local-secret-key-32-characters-ok
      BOOTSTRAP: "true"
      BOOTSTRAP_SAFE: "true"
      BOOTSTRAP_WORKSPACE_NAME: LocalWorkspace
      BOOTSTRAP_WORKSPACE_ADMIN_EMAIL: admin@local.test
      API_BASE_URL: http://localhost:3001
      CORS_ORIGIN: http://localhost:3000
      # ClickHouse placeholders (required by config)
      CLICKHOUSE_HOST: http://localhost:8123
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: ""
      CLICKHOUSE_DATABASE: dittofeed
      # Temporal placeholders
      TEMPORAL_ADDRESS: localhost:7233
      TEMPORAL_NAMESPACE: default
    ports:
      - "3001:3001"
    volumes:
      - ./packages/backend-lib/drizzle:/app/packages/backend-lib/drizzle
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

  dashboard:
    image: dittofeed-dashboard:local
    container_name: dittofeed_dashboard
    depends_on:
      api:
        condition: service_healthy
    environment:
      NODE_ENV: production
      AUTH_MODE: multi-tenant
      NEXTAUTH_SECRET: local-nextauth-secret-testing
      NEXTAUTH_URL: http://localhost:3000
      API_BASE_URL: http://api:3001
      NEXT_PUBLIC_API_BASE_URL: http://localhost:3001
      NEXT_PUBLIC_API_URL: http://localhost:3001
      GOOGLE_CLIENT_ID: dummy-client-id.apps.googleusercontent.com
      GOOGLE_CLIENT_SECRET: dummy-client-secret
    ports:
      - "3000:3000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

  worker:
    image: dittofeed-worker:local
    container_name: dittofeed_worker
    depends_on:
      - api
      - postgres
      - redis
    environment:
      NODE_ENV: production
      AUTH_MODE: multi-tenant
      DATABASE_URL: postgresql://dittofeed:localpass@postgres:5432/dittofeed
      REDIS_URL: redis://:localpass@redis:6379
      BOOTSTRAP_WORKER: "true"
      # Temporal placeholders
      TEMPORAL_ADDRESS: localhost:7233
      TEMPORAL_NAMESPACE: default

volumes:
  postgres_data:
  redis_data:

networks:
  default:
    name: dittofeed_local
EOF
    
    print_success "Docker Compose file created"
}

# Check if images exist
check_images() {
    print_header "Checking Docker Images"
    
    IMAGES_OK=true
    
    for image in "dittofeed-api:local" "dittofeed-dashboard:local" "dittofeed-worker:local"; do
        if docker images | grep -q "${image%:*}.*${image#*:}"; then
            print_success "Found: $image"
        else
            print_error "Missing: $image"
            IMAGES_OK=false
        fi
    done
    
    if [ "$IMAGES_OK" = false ]; then
        print_error "Some images are missing. Please run: ./deployment/build-local-images.sh"
        exit 1
    fi
}

# Initialize database
init_database() {
    print_header "Initializing Database"
    
    print_info "Waiting for database to be ready..."
    sleep 10
    
    # Check if tables exist
    TABLE_COUNT=$(docker exec dittofeed_postgres psql -U dittofeed -d dittofeed -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
    
    if [ "$TABLE_COUNT" = "0" ]; then
        print_warning "No tables found. Bootstrap should create them..."
        
        # Restart API to trigger bootstrap
        print_info "Restarting API to trigger bootstrap..."
        docker restart dittofeed_api
        sleep 15
        
        # Check again
        TABLE_COUNT=$(docker exec dittofeed_postgres psql -U dittofeed -d dittofeed -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
        
        if [ "$TABLE_COUNT" != "0" ]; then
            print_success "Database initialized with $TABLE_COUNT tables"
        else
            print_error "Database initialization failed - no tables created"
            print_info "Check API logs: docker logs dittofeed_api"
        fi
    else
        print_success "Database already has $TABLE_COUNT tables"
    fi
}

# Start services
start_services() {
    print_header "Starting Services"
    
    cd "$PROJECT_ROOT"
    
    # Stop any existing containers
    docker-compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    
    # Start services
    print_info "Starting services..."
    docker-compose -f "$COMPOSE_FILE" up -d
    
    # Wait for services
    print_info "Waiting for services to be ready..."
    sleep 15
    
    # Show status
    docker-compose -f "$COMPOSE_FILE" ps
}

# Test endpoints
test_endpoints() {
    print_header "Testing Endpoints"
    
    # Test API
    print_info "Testing API..."
    API_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/api 2>/dev/null || echo "000")
    if [ "$API_RESPONSE" = "200" ] || [ "$API_RESPONSE" = "404" ]; then
        print_success "API responding: HTTP $API_RESPONSE"
        
        # Get API version
        VERSION=$(curl -s http://localhost:3001/api 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        print_info "API Version: $VERSION"
    else
        print_error "API not responding: HTTP $API_RESPONSE"
    fi
    
    # Test Dashboard
    print_info "Testing Dashboard..."
    DASH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
    if [ "$DASH_RESPONSE" = "200" ] || [ "$DASH_RESPONSE" = "307" ] || [ "$DASH_RESPONSE" = "302" ]; then
        print_success "Dashboard responding: HTTP $DASH_RESPONSE"
    else
        print_error "Dashboard not responding: HTTP $DASH_RESPONSE"
    fi
    
    # Check database
    print_info "Checking database tables..."
    docker exec dittofeed_postgres psql -U dittofeed -d dittofeed -c "\dt" 2>/dev/null | head -20 || print_error "Could not list tables"
}

# Show logs
show_logs() {
    print_header "Recent Logs"
    
    echo -e "\n${BLUE}=== API Logs ===${NC}"
    docker logs dittofeed_api --tail 15 2>&1
    
    echo -e "\n${BLUE}=== Dashboard Logs ===${NC}"
    docker logs dittofeed_dashboard --tail 10 2>&1
}

# Main function
main() {
    case "${1:-}" in
        stop)
            print_info "Stopping services..."
            docker-compose -f "$COMPOSE_FILE" down
            print_success "Services stopped"
            exit 0
            ;;
        clean)
            print_info "Cleaning up..."
            docker-compose -f "$COMPOSE_FILE" down -v
            rm -f "$COMPOSE_FILE"
            print_success "Cleanup completed"
            exit 0
            ;;
        logs)
            docker-compose -f "$COMPOSE_FILE" logs -f
            exit 0
            ;;
        restart)
            print_info "Restarting services..."
            docker-compose -f "$COMPOSE_FILE" restart
            print_success "Services restarted"
            exit 0
            ;;
        status)
            docker-compose -f "$COMPOSE_FILE" ps
            exit 0
            ;;
    esac
    
    print_header "Dittofeed Local Deployment"
    
    check_images
    create_compose_file
    start_services
    init_database
    test_endpoints
    show_logs
    
    print_header "Deployment Ready"
    print_success "Local deployment is running!"
    echo ""
    echo "🌐 Access Points:"
    echo "   API:       http://localhost:3001"
    echo "   Dashboard: http://localhost:3000"
    echo "   Database:  postgresql://dittofeed:localpass@localhost:5433/dittofeed"
    echo "   Redis:     redis://:localpass@localhost:6379"
    echo ""
    echo "📝 Commands:"
    echo "   View logs:   $0 logs"
    echo "   Status:      $0 status"
    echo "   Restart:     $0 restart"
    echo "   Stop:        $0 stop"
    echo "   Clean:       $0 clean"
    echo ""
    echo "🔍 Debug:"
    echo "   API logs:    docker logs dittofeed_api -f"
    echo "   DB shell:    docker exec -it dittofeed_postgres psql -U dittofeed -d dittofeed"
    echo "   Redis CLI:   docker exec -it dittofeed_redis redis-cli -a localpass"
}

main "$@"