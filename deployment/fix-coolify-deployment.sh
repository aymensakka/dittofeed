#!/bin/bash

# ==============================================================================
# Fix Dittofeed Multi-Tenant Deployment on Coolify
# ==============================================================================
# This script fixes the database initialization issue in production
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

# Check if we have the migration file
if [ ! -f "deployment/init-database.sql" ]; then
    print_error "Migration file not found. Creating it..."
    cat packages/backend-lib/drizzle/*.sql > deployment/init-database.sql
    print_success "Created deployment/init-database.sql"
fi

print_header "Dittofeed Coolify Deployment Fix"

# Configuration
REMOTE_HOST="${1:-}"
REMOTE_USER="${2:-root}"

if [ -z "$REMOTE_HOST" ]; then
    print_error "Usage: $0 <coolify-server-ip> [username]"
    echo "Example: $0 192.168.1.100 root"
    exit 1
fi

print_info "Target server: $REMOTE_USER@$REMOTE_HOST"

# Step 1: Copy migration file to server
print_header "Step 1: Copying Migration File"
print_info "Uploading init-database.sql to server..."

scp deployment/init-database.sql "$REMOTE_USER@$REMOTE_HOST:/tmp/init-database.sql" || {
    print_error "Failed to copy migration file"
    exit 1
}

print_success "Migration file uploaded"

# Step 2: Create fix script on server
print_header "Step 2: Creating Fix Script"

cat <<'REMOTE_SCRIPT' | ssh "$REMOTE_USER@$REMOTE_HOST" "cat > /tmp/fix-dittofeed.sh && chmod +x /tmp/fix-dittofeed.sh"
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Finding Dittofeed containers...${NC}"

# Find PostgreSQL container
POSTGRES_CONTAINER=$(docker ps | grep postgres | grep -v supabase | head -1 | awk '{print $1}')
if [ -z "$POSTGRES_CONTAINER" ]; then
    echo -e "${RED}PostgreSQL container not found${NC}"
    exit 1
fi
echo -e "${GREEN}Found PostgreSQL: $POSTGRES_CONTAINER${NC}"

# Find API container
API_CONTAINER=$(docker ps | grep "api-" | head -1 | awk '{print $1}')
if [ -z "$API_CONTAINER" ]; then
    echo -e "${RED}API container not found${NC}"
    exit 1
fi
echo -e "${GREEN}Found API: $API_CONTAINER${NC}"

# Find Dashboard container
DASHBOARD_CONTAINER=$(docker ps | grep "dashboard-" | head -1 | awk '{print $1}')
echo -e "${GREEN}Found Dashboard: $DASHBOARD_CONTAINER${NC}"

# Check current database status
echo -e "\n${BLUE}Checking database status...${NC}"
TABLE_COUNT=$(docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d dittofeed -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
echo -e "Current table count: $TABLE_COUNT"

if [ "$TABLE_COUNT" -eq "0" ]; then
    echo -e "${YELLOW}No tables found. Initializing database...${NC}"
    
    # Apply migrations
    docker exec -i "$POSTGRES_CONTAINER" psql -U dittofeed -d dittofeed < /tmp/init-database.sql
    
    # Verify tables created
    NEW_TABLE_COUNT=$(docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d dittofeed -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
    
    if [ "$NEW_TABLE_COUNT" -gt "0" ]; then
        echo -e "${GREEN}✅ Database initialized with $NEW_TABLE_COUNT tables${NC}"
    else
        echo -e "${RED}❌ Database initialization failed${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Database already has $TABLE_COUNT tables${NC}"
fi

# Create initial workspace if needed
echo -e "\n${BLUE}Checking for workspaces...${NC}"
WORKSPACE_COUNT=$(docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d dittofeed -tAc "SELECT COUNT(*) FROM \"Workspace\";" 2>/dev/null || echo "0")

if [ "$WORKSPACE_COUNT" -eq "0" ]; then
    echo -e "${YELLOW}No workspaces found. Creating default workspace...${NC}"
    
    docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d dittofeed -c "
    INSERT INTO \"Workspace\" (id, name, type, \"createdAt\", \"updatedAt\") 
    VALUES (gen_random_uuid(), 'Default', 'Root', NOW(), NOW())
    ON CONFLICT DO NOTHING;"
    
    echo -e "${GREEN}✅ Default workspace created${NC}"
else
    echo -e "${GREEN}Found $WORKSPACE_COUNT workspace(s)${NC}"
fi

# Restart services
echo -e "\n${BLUE}Restarting services...${NC}"
docker restart "$API_CONTAINER"
[ -n "$DASHBOARD_CONTAINER" ] && docker restart "$DASHBOARD_CONTAINER"

echo -e "${GREEN}✅ Services restarted${NC}"

# Test API
echo -e "\n${BLUE}Testing API...${NC}"
sleep 10
API_IP=$(docker inspect "$API_CONTAINER" -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)
if [ -n "$API_IP" ]; then
    curl -s "http://$API_IP:3001/api" || echo "API not responding yet"
fi

echo -e "\n${GREEN}✅ Fix applied successfully!${NC}"
echo -e "\nNext steps:"
echo -e "1. Update Cloudflare tunnel if needed"
echo -e "2. Test at https://communication-api.caramelme.com/api"
echo -e "3. Access dashboard at https://communication-dashboard.caramelme.com"
REMOTE_SCRIPT

print_success "Fix script created on server"

# Step 3: Execute fix
print_header "Step 3: Executing Fix"
print_info "Running fix script on server..."

ssh "$REMOTE_USER@$REMOTE_HOST" "/tmp/fix-dittofeed.sh" || {
    print_error "Fix execution failed"
    exit 1
}

# Step 4: Cleanup
print_header "Step 4: Cleanup"
ssh "$REMOTE_USER@$REMOTE_HOST" "rm -f /tmp/init-database.sql /tmp/fix-dittofeed.sh"
print_success "Temporary files removed"

# Step 5: Test deployment
print_header "Step 5: Testing Deployment"

print_info "Testing API endpoint..."
API_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" https://communication-api.caramelme.com/api 2>/dev/null || echo "000")

if [ "$API_RESPONSE" = "200" ]; then
    print_success "API responding: HTTP $API_RESPONSE"
else
    print_error "API not accessible: HTTP $API_RESPONSE"
fi

print_info "Testing Dashboard..."
DASH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" https://communication-dashboard.caramelme.com 2>/dev/null || echo "000")

if [ "$DASH_RESPONSE" = "200" ] || [ "$DASH_RESPONSE" = "307" ]; then
    print_success "Dashboard responding: HTTP $DASH_RESPONSE"
else
    print_error "Dashboard not accessible: HTTP $DASH_RESPONSE"
fi

print_header "Fix Complete"
print_success "Database initialization fix has been applied!"
echo ""
echo "Access your Dittofeed instance:"
echo "  Dashboard: https://communication-dashboard.caramelme.com"
echo "  API: https://communication-api.caramelme.com"
echo ""
echo "If issues persist:"
echo "1. Check container logs on Coolify"
echo "2. Verify Cloudflare tunnel status"
echo "3. Ensure environment variables are set correctly"