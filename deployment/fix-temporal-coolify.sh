#!/bin/bash

# ==============================================================================
# Fix Temporal Database Connection in Coolify
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}Fixing Temporal Database Connection${NC}"
echo -e "${BLUE}===================================================${NC}"

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
    echo -e "${GREEN}✓ Loaded environment variables${NC}"
else
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi

# SSH into server and fix
ssh -o StrictHostKeyChecking=no root@$SERVER_IP << 'EOF'
set -e

PROJECT_ID="p0gcsc088cogco0cokco4404"
POSTGRES_PASSWORD="LOpnL3wYIbWUBax4qXeR"

echo "Creating missing volumes..."
docker volume create ${PROJECT_ID}_clickhouse-data || true
docker volume create ${PROJECT_ID}_clickhouse-logs || true

echo "Checking PostgreSQL container..."
POSTGRES_CONTAINER=$(docker ps -a --format '{{.Names}}' | grep -E "postgres.*${PROJECT_ID}" | head -1)
if [ ! -z "$POSTGRES_CONTAINER" ]; then
    echo "PostgreSQL container: $POSTGRES_CONTAINER"
    
    # Check if databases exist
    echo "Checking for temporal databases..."
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d postgres -c "SELECT datname FROM pg_database WHERE datname IN ('temporal', 'temporal_visibility');" || true
    
    # Create databases if they don't exist
    echo "Creating temporal databases..."
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d postgres -c "CREATE DATABASE temporal;" 2>/dev/null || echo "Database 'temporal' already exists or error occurred"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d postgres -c "CREATE DATABASE temporal_visibility;" 2>/dev/null || echo "Database 'temporal_visibility' already exists or error occurred"
    
    # Grant permissions
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE temporal TO dittofeed;" || true
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE temporal_visibility TO dittofeed;" || true
    
    # Update pg_hba.conf to allow temporal connections
    echo "Updating PostgreSQL authentication..."
    docker exec $POSTGRES_CONTAINER bash -c "echo 'host    temporal            dittofeed    0.0.0.0/0    md5' >> /var/lib/postgresql/data/pg_hba.conf" || true
    docker exec $POSTGRES_CONTAINER bash -c "echo 'host    temporal_visibility dittofeed    0.0.0.0/0    md5' >> /var/lib/postgresql/data/pg_hba.conf" || true
    
    # Reload PostgreSQL configuration
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d postgres -c "SELECT pg_reload_conf();" || true
fi

# Check Temporal logs
echo "Checking Temporal container logs..."
TEMPORAL_CONTAINER=$(docker ps -a --format '{{.Names}}' | grep -E "temporal.*${PROJECT_ID}" | head -1)
if [ ! -z "$TEMPORAL_CONTAINER" ]; then
    echo "Recent Temporal logs:"
    docker logs $TEMPORAL_CONTAINER --tail 30 2>&1 | grep -E "(error|ERROR|fail|FAIL|Unable|unable)" || echo "No errors found in recent logs"
fi

echo "Fix applied. Temporal should now be able to connect to PostgreSQL."
EOF

echo -e "\n${GREEN}===================================================${NC}"
echo -e "${GREEN}Temporal fix completed!${NC}"
echo -e "${GREEN}===================================================${NC}"
echo ""
echo "Next steps:"
echo "1. Redeploy the application in Coolify"
echo "2. Monitor Temporal container health"
echo "3. Check if all services start successfully"