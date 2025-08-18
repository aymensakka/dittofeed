#!/bin/bash

# ==============================================================================
# Initialize Coolify Deployment - Run this ONCE on the server
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}Initializing Coolify Deployment${NC}"
echo -e "${BLUE}===================================================${NC}"

# Wait for PostgreSQL to be ready
echo -e "\n${YELLOW}Waiting for PostgreSQL...${NC}"
POSTGRES_CONTAINER=$(docker ps | grep postgres | grep p0gcsc088cogco0cokco4404 | awk '{print $1}')

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo -e "${RED}PostgreSQL container not found. Make sure Coolify has started the containers.${NC}"
    exit 1
fi

# Wait for PostgreSQL to be ready
for i in {1..30}; do
    if docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d postgres -c "SELECT 1" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL is ready${NC}"
        break
    fi
    echo -n "."
    sleep 2
done

# Create Temporal databases
echo -e "\n${YELLOW}Creating Temporal databases...${NC}"
docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d postgres -c "CREATE DATABASE temporal" 2>/dev/null || echo "temporal database already exists"
docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d postgres -c "CREATE DATABASE temporal_visibility" 2>/dev/null || echo "temporal_visibility database already exists"
echo -e "${GREEN}✓ Temporal databases created${NC}"

# Initialize ClickHouse database
echo -e "\n${YELLOW}Initializing ClickHouse...${NC}"
CLICKHOUSE_CONTAINER=$(docker ps | grep clickhouse | grep p0gcsc088cogco0cokco4404 | awk '{print $1}')

if [ -n "$CLICKHOUSE_CONTAINER" ]; then
    # Wait for ClickHouse to be ready
    for i in {1..30}; do
        if docker exec "$CLICKHOUSE_CONTAINER" clickhouse-client --query "SELECT 1" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ ClickHouse is ready${NC}"
            docker exec "$CLICKHOUSE_CONTAINER" clickhouse-client --query "CREATE DATABASE IF NOT EXISTS dittofeed"
            echo -e "${GREEN}✓ ClickHouse database created${NC}"
            break
        fi
        echo -n "."
        sleep 2
    done
fi

# Initialize Dittofeed database schema if needed
echo -e "\n${YELLOW}Checking Dittofeed database schema...${NC}"
TABLE_COUNT=$(docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d dittofeed -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")

if [ "$TABLE_COUNT" -eq "0" ]; then
    echo -e "${YELLOW}Database is empty. You may need to run migrations.${NC}"
    echo "The API service will initialize the database on first run."
else
    echo -e "${GREEN}✓ Database has $TABLE_COUNT tables${NC}"
fi

echo -e "\n${GREEN}===================================================${NC}"
echo -e "${GREEN}Initialization Complete!${NC}"
echo -e "${GREEN}===================================================${NC}"
echo ""
echo "Now you can redeploy in Coolify and Temporal should start successfully."
echo ""
echo "If Temporal still fails, check the logs:"
echo "  docker logs \$(docker ps | grep temporal | grep p0gcsc088cogco0cokco4404 | awk '{print \$1}')"