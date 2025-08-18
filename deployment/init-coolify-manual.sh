#!/bin/bash

# ==============================================================================
# Manual Coolify Initialization - Run this on the server
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

# Find PostgreSQL container
echo -e "\n${YELLOW}Finding PostgreSQL container...${NC}"
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep postgres | grep p0gcsc088cogco0cokco4404 || true)

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo -e "${RED}PostgreSQL container not found. Make sure Coolify has deployed the stack.${NC}"
    echo "Available containers:"
    docker ps --format 'table {{.Names}}\t{{.Status}}'
    exit 1
fi

echo -e "${GREEN}Found PostgreSQL: $POSTGRES_CONTAINER${NC}"

# Wait for PostgreSQL to be ready
echo -e "\n${YELLOW}Waiting for PostgreSQL to be ready...${NC}"
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
docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d postgres -c "CREATE DATABASE IF NOT EXISTS temporal" 2>/dev/null || echo "temporal database already exists"
docker exec "$POSTGRES_CONTAINER" psql -U dittofeed -d postgres -c "CREATE DATABASE IF NOT EXISTS temporal_visibility" 2>/dev/null || echo "temporal_visibility database already exists"
echo -e "${GREEN}✓ Temporal databases created${NC}"

# Find and initialize ClickHouse
echo -e "\n${YELLOW}Finding ClickHouse container...${NC}"
CLICKHOUSE_CONTAINER=$(docker ps --format '{{.Names}}' | grep clickhouse | grep p0gcsc088cogco0cokco4404 || true)

if [ -n "$CLICKHOUSE_CONTAINER" ]; then
    echo -e "${GREEN}Found ClickHouse: $CLICKHOUSE_CONTAINER${NC}"
    
    # Wait for ClickHouse to be ready
    echo -e "${YELLOW}Waiting for ClickHouse...${NC}"
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
else
    echo -e "${YELLOW}ClickHouse container not found (will be created when you redeploy)${NC}"
fi

# Check Temporal status
echo -e "\n${YELLOW}Checking Temporal container...${NC}"
TEMPORAL_CONTAINER=$(docker ps -a --format '{{.Names}}' | grep temporal | grep p0gcsc088cogco0cokco4404 || true)

if [ -n "$TEMPORAL_CONTAINER" ]; then
    STATUS=$(docker inspect "$TEMPORAL_CONTAINER" --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
    echo "Temporal container status: $STATUS"
    
    if [ "$STATUS" != "running" ]; then
        echo -e "${YELLOW}Temporal is not running. After running this script, redeploy in Coolify.${NC}"
    fi
else
    echo -e "${YELLOW}Temporal container not found (will be created when you redeploy)${NC}"
fi

echo -e "\n${GREEN}===================================================${NC}"
echo -e "${GREEN}Initialization Complete!${NC}"
echo -e "${GREEN}===================================================${NC}"
echo ""
echo "Next steps:"
echo "1. Go to your Coolify dashboard"
echo "2. Navigate to your Dittofeed application"
echo "3. Click 'Redeploy' to restart all services"
echo "4. Temporal should now start successfully"
echo ""
echo "To check container status:"
echo "  docker ps | grep p0gcsc088cogco0cokco4404"
echo ""
echo "To check Temporal logs after redeploy:"
echo "  docker logs \$(docker ps -a --format '{{.Names}}' | grep temporal | grep p0gcsc088cogco0cokco4404) --tail 50"