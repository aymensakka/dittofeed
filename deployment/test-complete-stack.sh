#!/bin/bash

# ==============================================================================
# Test Complete Stack with Password Fix
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}Testing Complete Stack with Consistent Passwords${NC}"
echo -e "${BLUE}===================================================${NC}"

# Clean up any existing containers
echo -e "\n${YELLOW}Cleaning up existing containers...${NC}"
docker compose -f docker-compose.coolify.yaml down -v 2>/dev/null || true

# Source the .env file to use the actual passwords
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
    echo -e "${GREEN}✓ Loaded environment variables from .env${NC}"
else
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi

# Display the passwords being used (masked)
echo -e "\n${BLUE}Configuration:${NC}"
echo "POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:0:4}****"
echo "REDIS_PASSWORD: ${REDIS_PASSWORD:0:4}****"
echo "CLICKHOUSE_PASSWORD: ${CLICKHOUSE_PASSWORD:0:4}****"

# Start PostgreSQL first
echo -e "\n${YELLOW}Starting PostgreSQL...${NC}"
docker compose -f docker-compose.coolify.yaml up -d postgres
sleep 10

# Check PostgreSQL
echo -e "\n${BLUE}Testing PostgreSQL connection...${NC}"
if docker exec $(docker ps -q -f name=postgres) psql -U dittofeed -d postgres -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PostgreSQL is working${NC}"
    
    # Create databases for Temporal
    echo -e "${YELLOW}Creating Temporal databases...${NC}"
    docker exec $(docker ps -q -f name=postgres) psql -U dittofeed -d postgres -c "CREATE DATABASE temporal" 2>/dev/null || echo "temporal database exists"
    docker exec $(docker ps -q -f name=postgres) psql -U dittofeed -d postgres -c "CREATE DATABASE temporal_visibility" 2>/dev/null || echo "temporal_visibility database exists"
else
    echo -e "${RED}✗ PostgreSQL connection failed${NC}"
    docker logs $(docker ps -q -f name=postgres) --tail 20
    exit 1
fi

# Start Redis
echo -e "\n${YELLOW}Starting Redis...${NC}"
docker compose -f docker-compose.coolify.yaml up -d redis
sleep 5

# Test Redis
echo -e "\n${BLUE}Testing Redis...${NC}"
if docker exec $(docker ps -q -f name=redis) redis-cli ping | grep -q PONG; then
    echo -e "${GREEN}✓ Redis is working${NC}"
else
    echo -e "${RED}✗ Redis connection failed${NC}"
    docker logs $(docker ps -q -f name=redis) --tail 20
fi

# Start ClickHouse
echo -e "\n${YELLOW}Starting ClickHouse...${NC}"
docker compose -f docker-compose.coolify.yaml up -d clickhouse
sleep 15

# Test ClickHouse
echo -e "\n${BLUE}Testing ClickHouse...${NC}"
if docker exec $(docker ps -q -f name=clickhouse) clickhouse-client --query "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ ClickHouse is working${NC}"
    
    # Create Dittofeed database
    docker exec $(docker ps -q -f name=clickhouse) clickhouse-client --query "CREATE DATABASE IF NOT EXISTS dittofeed"
else
    echo -e "${RED}✗ ClickHouse connection failed${NC}"
    docker logs $(docker ps -q -f name=clickhouse) --tail 20
fi

# Start Temporal with retry logic
echo -e "\n${YELLOW}Starting Temporal (may take a few attempts)...${NC}"
docker compose -f docker-compose.coolify.yaml up -d temporal

# Wait for Temporal with multiple retries
TEMPORAL_READY=false
for i in {1..10}; do
    sleep 10
    echo -n "Attempt $i: "
    
    # Check if container is running
    if docker ps | grep -q temporal; then
        # Check if it's not restarting
        STATUS=$(docker inspect $(docker ps -q -f name=temporal) --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
        if [ "$STATUS" == "running" ]; then
            # Try to connect to Temporal
            if docker exec $(docker ps -q -f name=temporal) tctl cluster health 2>/dev/null | grep -q SERVING; then
                echo -e "${GREEN}Temporal is ready!${NC}"
                TEMPORAL_READY=true
                break
            else
                echo "Temporal not ready yet..."
            fi
        else
            echo "Temporal status: $STATUS"
        fi
    else
        echo "Temporal container not found, restarting..."
        docker compose -f docker-compose.coolify.yaml up -d temporal
    fi
done

if [ "$TEMPORAL_READY" = false ]; then
    echo -e "${YELLOW}⚠ Temporal is not fully ready, but continuing...${NC}"
    echo "Temporal logs:"
    docker logs $(docker ps -aq -f name=temporal) --tail 20 2>/dev/null || true
fi

# Show final status
echo -e "\n${BLUE}===================================================${NC}"
echo -e "${BLUE}Service Status:${NC}"
echo -e "${BLUE}===================================================${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(postgres|redis|clickhouse|temporal)" || true

echo -e "\n${GREEN}Testing complete!${NC}"
echo ""
echo "To start the API and other services:"
echo "  docker compose -f docker-compose.coolify.yaml up -d api dashboard worker"
echo ""
echo "To check logs:"
echo "  docker logs <container-name> --tail 50"
echo ""
echo "To stop everything:"
echo "  docker compose -f docker-compose.coolify.yaml down"