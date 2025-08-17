#!/bin/bash

# ==============================================================================
# Dittofeed Local Multi-Tenant Deployment and Testing Script
# ==============================================================================
# This script helps you build and deploy Dittofeed locally to debug issues
# before deploying to production (Coolify)
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$SCRIPT_DIR/local-test-$TIMESTAMP.log"

# Function to print colored output
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

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check Docker
    if command -v docker &> /dev/null; then
        print_success "Docker installed: $(docker --version)"
    else
        print_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker Compose
    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        print_success "Docker Compose installed"
    else
        print_error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check Node.js
    if command -v node &> /dev/null; then
        print_success "Node.js installed: $(node --version)"
    else
        print_error "Node.js is not installed"
        exit 1
    fi
    
    # Check Yarn
    if command -v yarn &> /dev/null; then
        print_success "Yarn installed: $(yarn --version)"
    else
        print_error "Yarn is not installed"
        exit 1
    fi
}

# Clean up previous deployment
cleanup_existing() {
    print_header "Cleaning Up Previous Deployment"
    
    # Stop existing containers
    print_info "Stopping existing containers..."
    docker-compose -f "$PROJECT_ROOT/docker-compose.local.yaml" down 2>/dev/null || true
    
    # Remove volumes for clean state
    if [[ "$1" == "--clean" ]]; then
        print_warning "Removing existing volumes (clean install)..."
        docker volume rm dittofeed-multitenant_postgres_data_local 2>/dev/null || true
        docker volume rm dittofeed-multitenant_redis_data_local 2>/dev/null || true
    fi
    
    print_success "Cleanup completed"
}

# Build the application
build_application() {
    print_header "Building Application"
    
    cd "$PROJECT_ROOT"
    
    # Install dependencies
    print_info "Installing dependencies..."
    yarn install
    
    # Build all packages
    print_info "Building packages..."
    yarn build
    
    # Build Docker images
    print_info "Building Docker images..."
    
    # Build API image
    docker build -f packages/api/Dockerfile.multitenant \
        --build-arg AUTH_MODE=multi-tenant \
        --build-arg BOOTSTRAP=true \
        --build-arg BOOTSTRAP_SAFE=true \
        -t dittofeed-api:local-test .
    
    # Build Dashboard image
    docker build -f packages/dashboard/Dockerfile.multitenant \
        --build-arg AUTH_MODE=multi-tenant \
        -t dittofeed-dashboard:local-test .
    
    # Build Worker image
    docker build -f packages/worker/Dockerfile.multitenant \
        --build-arg AUTH_MODE=multi-tenant \
        -t dittofeed-worker:local-test .
    
    print_success "Build completed"
}

# Create local environment file
create_env_file() {
    print_header "Creating Local Environment Configuration"
    
    cat > "$PROJECT_ROOT/.env.local" <<EOF
# Local Multi-Tenant Testing Configuration
NODE_ENV=development

# Authentication
AUTH_MODE=multi-tenant
MULTITENANCY_ENABLED=true
WORKSPACE_ISOLATION_ENABLED=true

# Database
DATABASE_URL=postgresql://dittofeed:localpass123@localhost:5433/dittofeed
POSTGRES_PASSWORD=localpass123

# Redis
REDIS_URL=redis://:localpass123@localhost:6380
REDIS_PASSWORD=localpass123

# Security Keys (local testing only)
JWT_SECRET=local-jwt-secret-32-chars-minimum-required
ENCRYPTION_KEY=local-encryption-key-32-chars-ok
NEXTAUTH_SECRET=local-nextauth-secret-for-testing
SECRET_KEY=local-secret-key-32-chars-minimum

# URLs
API_BASE_URL=http://localhost:3001
DASHBOARD_URL=http://localhost:3002
NEXTAUTH_URL=http://localhost:3002
NEXT_PUBLIC_API_BASE_URL=http://localhost:3001
CORS_ORIGIN=http://localhost:3002

# Bootstrap
BOOTSTRAP=true
BOOTSTRAP_SAFE=true
BOOTSTRAP_WORKER=true
BOOTSTRAP_WORKSPACE_NAME=LocalTestWorkspace
BOOTSTRAP_WORKSPACE_ADMIN_EMAIL=admin@local.test

# Google OAuth (dummy for local testing)
GOOGLE_CLIENT_ID=dummy-client-id-for-local-testing
GOOGLE_CLIENT_SECRET=dummy-client-secret-for-local-testing

# Email Provider (optional for local)
AWS_SES_REGION=us-east-1
AWS_ACCESS_KEY_ID=dummy-access-key
AWS_SECRET_ACCESS_KEY=dummy-secret-key
EOF
    
    print_success "Environment file created: .env.local"
}

# Create docker-compose for local testing
create_docker_compose() {
    print_header "Creating Docker Compose Configuration"
    
    cat > "$PROJECT_ROOT/docker-compose.local-test.yaml" <<'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: dittofeed_postgres_test
    environment:
      POSTGRES_DB: dittofeed
      POSTGRES_USER: dittofeed
      POSTGRES_PASSWORD: localpass123
    volumes:
      - postgres_test_data:/var/lib/postgresql/data
    ports:
      - "5433:5432"
    networks:
      - dittofeed_test
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dittofeed -d dittofeed"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: dittofeed_redis_test
    command: redis-server --requirepass localpass123
    volumes:
      - redis_test_data:/data
    ports:
      - "6380:6379"
    networks:
      - dittofeed_test
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "localpass123", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  api:
    image: dittofeed-api:local-test
    container_name: dittofeed_api_test
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      NODE_ENV: development
      PORT: 3001
      AUTH_MODE: multi-tenant
      MULTITENANCY_ENABLED: "true"
      WORKSPACE_ISOLATION_ENABLED: "true"
      DATABASE_URL: postgresql://dittofeed:localpass123@postgres:5432/dittofeed
      REDIS_URL: redis://:localpass123@redis:6379
      JWT_SECRET: local-jwt-secret-32-chars-minimum-required
      ENCRYPTION_KEY: local-encryption-key-32-chars-ok
      SECRET_KEY: local-secret-key-32-chars-minimum
      BOOTSTRAP: "true"
      BOOTSTRAP_SAFE: "true"
      BOOTSTRAP_WORKSPACE_NAME: LocalTestWorkspace
      BOOTSTRAP_WORKSPACE_ADMIN_EMAIL: admin@local.test
      API_BASE_URL: http://localhost:3001
      CORS_ORIGIN: http://localhost:3002
    ports:
      - "3001:3001"
    networks:
      - dittofeed_test
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  dashboard:
    image: dittofeed-dashboard:local-test
    container_name: dittofeed_dashboard_test
    depends_on:
      - api
    environment:
      NODE_ENV: development
      AUTH_MODE: multi-tenant
      NEXTAUTH_SECRET: local-nextauth-secret-for-testing
      NEXTAUTH_URL: http://localhost:3002
      API_BASE_URL: http://api:3001
      NEXT_PUBLIC_API_BASE_URL: http://localhost:3001
      GOOGLE_CLIENT_ID: dummy-client-id-for-local-testing
      GOOGLE_CLIENT_SECRET: dummy-client-secret-for-local-testing
    ports:
      - "3002:3000"
    networks:
      - dittofeed_test
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  worker:
    image: dittofeed-worker:local-test
    container_name: dittofeed_worker_test
    depends_on:
      - api
      - postgres
      - redis
    environment:
      NODE_ENV: development
      AUTH_MODE: multi-tenant
      DATABASE_URL: postgresql://dittofeed:localpass123@postgres:5432/dittofeed
      REDIS_URL: redis://:localpass123@redis:6379
      BOOTSTRAP_WORKER: "true"
    networks:
      - dittofeed_test

networks:
  dittofeed_test:
    driver: bridge

volumes:
  postgres_test_data:
  redis_test_data:
EOF
    
    print_success "Docker Compose configuration created"
}

# Start the deployment
start_deployment() {
    print_header "Starting Local Deployment"
    
    cd "$PROJECT_ROOT"
    
    # Start services
    print_info "Starting services with docker-compose..."
    docker-compose -f docker-compose.local-test.yaml up -d
    
    # Wait for services to be healthy
    print_info "Waiting for services to be healthy..."
    sleep 10
    
    # Check service status
    docker-compose -f docker-compose.local-test.yaml ps
    
    print_success "Services started"
}

# Initialize database
initialize_database() {
    print_header "Initializing Database"
    
    print_info "Waiting for database to be ready..."
    sleep 5
    
    # Check if tables exist
    TABLE_COUNT=$(docker exec dittofeed_postgres_test psql -U dittofeed -d dittofeed -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
    
    if [[ "$TABLE_COUNT" -eq "0" ]]; then
        print_warning "No tables found, running migrations..."
        
        # Run migrations from API container
        docker exec dittofeed_api_test yarn migrate || {
            print_error "Migration failed, trying manual approach..."
            
            # Try to run migrations manually
            cd "$PROJECT_ROOT/packages/backend-lib"
            DATABASE_URL=postgresql://dittofeed:localpass123@localhost:5433/dittofeed yarn drizzle-kit push:pg
        }
    else
        print_success "Database already has $TABLE_COUNT tables"
    fi
    
    print_success "Database initialization completed"
}

# Test endpoints
test_endpoints() {
    print_header "Testing Endpoints"
    
    # Function to test an endpoint
    test_endpoint() {
        local url=$1
        local name=$2
        
        response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        
        if [[ "$response" == "200" ]] || [[ "$response" == "301" ]] || [[ "$response" == "302" ]]; then
            print_success "$name: HTTP $response"
            return 0
        else
            print_error "$name: HTTP $response"
            return 1
        fi
    }
    
    # Test API endpoints
    test_endpoint "http://localhost:3001/api" "API Root"
    test_endpoint "http://localhost:3001/health" "API Health"
    
    # Test Dashboard
    test_endpoint "http://localhost:3002" "Dashboard Root"
    test_endpoint "http://localhost:3002/login" "Dashboard Login"
    
    # Test database connection
    print_info "Testing database connection..."
    docker exec dittofeed_postgres_test psql -U dittofeed -d dittofeed -c "SELECT version();" &>/dev/null && \
        print_success "Database connection: OK" || \
        print_error "Database connection: Failed"
    
    # Test Redis connection
    print_info "Testing Redis connection..."
    docker exec dittofeed_redis_test redis-cli -a localpass123 ping &>/dev/null && \
        print_success "Redis connection: OK" || \
        print_error "Redis connection: Failed"
}

# Show logs
show_logs() {
    print_header "Recent Logs"
    
    print_info "API Logs:"
    docker logs dittofeed_api_test --tail 20 2>&1 | sed 's/^/  /'
    
    print_info "Dashboard Logs:"
    docker logs dittofeed_dashboard_test --tail 20 2>&1 | sed 's/^/  /'
}

# Main execution
main() {
    print_header "Dittofeed Local Multi-Tenant Testing"
    echo "Log file: $LOG_FILE"
    
    # Parse arguments
    CLEAN_INSTALL=false
    BUILD_ONLY=false
    SKIP_BUILD=false
    
    for arg in "$@"; do
        case $arg in
            --clean)
                CLEAN_INSTALL=true
                ;;
            --build-only)
                BUILD_ONLY=true
                ;;
            --skip-build)
                SKIP_BUILD=true
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --clean       Remove existing data and start fresh"
                echo "  --build-only  Only build images, don't deploy"
                echo "  --skip-build  Skip building, use existing images"
                echo "  --help        Show this help message"
                exit 0
                ;;
        esac
    done
    
    # Execute steps
    check_prerequisites
    
    if [[ "$CLEAN_INSTALL" == true ]]; then
        cleanup_existing --clean
    else
        cleanup_existing
    fi
    
    if [[ "$SKIP_BUILD" != true ]]; then
        build_application
    fi
    
    if [[ "$BUILD_ONLY" == true ]]; then
        print_success "Build completed. Exiting."
        exit 0
    fi
    
    create_env_file
    create_docker_compose
    start_deployment
    initialize_database
    test_endpoints
    show_logs
    
    print_header "Deployment Summary"
    print_success "Local multi-tenant deployment is ready!"
    echo ""
    echo "Access Points:"
    echo "  API:       http://localhost:3001"
    echo "  Dashboard: http://localhost:3002"
    echo "  Database:  postgresql://dittofeed:localpass123@localhost:5433/dittofeed"
    echo "  Redis:     redis://:localpass123@localhost:6380"
    echo ""
    echo "Next Steps:"
    echo "1. Open http://localhost:3002 in your browser"
    echo "2. Test authentication flow"
    echo "3. Debug any issues locally"
    echo "4. Apply fixes to production deployment"
    echo ""
    echo "Commands:"
    echo "  View logs:    docker-compose -f docker-compose.local-test.yaml logs -f"
    echo "  Stop:         docker-compose -f docker-compose.local-test.yaml down"
    echo "  Clean stop:   docker-compose -f docker-compose.local-test.yaml down -v"
}

# Run main function
main "$@"