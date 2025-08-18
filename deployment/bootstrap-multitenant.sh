#!/bin/bash

# ==============================================================================
# Bootstrap Multi-Tenant Dittofeed on Server
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}Bootstrapping Multi-Tenant Dittofeed${NC}"
echo -e "${BLUE}===================================================${NC}"

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
    echo -e "${GREEN}✓ Loaded environment variables${NC}"
else
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi

# Configuration for bootstrap
WORKSPACE_NAME="${BOOTSTRAP_WORKSPACE_NAME:-Default}"
WORKSPACE_DOMAIN="${BOOTSTRAP_WORKSPACE_DOMAIN:-caramelme.com}"
WORKSPACE_TYPE="${BOOTSTRAP_WORKSPACE_TYPE:-Root}"

echo -e "\n${YELLOW}Bootstrap Configuration:${NC}"
echo "Workspace Name: $WORKSPACE_NAME"
echo "Workspace Domain: $WORKSPACE_DOMAIN"
echo "Workspace Type: $WORKSPACE_TYPE"

# SSH into server and run bootstrap
ssh -o StrictHostKeyChecking=no root@$SERVER_IP << EOF
set -e

PROJECT_ID="p0gcsc088cogco0cokco4404"

echo -e "\n${YELLOW}Finding API container...${NC}"
API_CONTAINER=\$(docker ps --format '{{.Names}}' | grep -E "api.*\${PROJECT_ID}" | head -1)

if [ -z "\$API_CONTAINER" ]; then
    echo -e "${RED}✗ API container not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found API container: \$API_CONTAINER${NC}"

echo -e "\n${YELLOW}Running database migrations...${NC}"
docker exec \$API_CONTAINER sh -c "cd /app && npx drizzle-kit migrate" 2>&1 || echo "Migration attempt 1"

# Alternative migration command if the first fails
docker exec \$API_CONTAINER sh -c "cd /app && node -e 'require(\"backend-lib/dist/migrate\").drizzleMigrate().then(() => console.log(\"Migration complete\")).catch(e => console.error(\"Migration failed:\", e))'" 2>&1 || echo "Migration attempt 2"

echo -e "\n${YELLOW}Running bootstrap to create workspace...${NC}"
# Try different bootstrap approaches
echo "Attempt 1: Using bootstrap script directly"
docker exec \$API_CONTAINER sh -c "cd /app && node -e '
const bootstrap = require(\"backend-lib/dist/bootstrap\").default;
bootstrap({
  workspaceName: \"$WORKSPACE_NAME\",
  workspaceDomain: \"$WORKSPACE_DOMAIN\",
  workspaceType: \"$WORKSPACE_TYPE\"
}).then(result => {
  console.log(\"Bootstrap successful:\", result);
  process.exit(0);
}).catch(err => {
  console.error(\"Bootstrap failed:\", err);
  process.exit(1);
});
'" 2>&1 || echo "Bootstrap attempt 1 failed"

# Alternative: Using the bootstrapWithDefaults function
echo "Attempt 2: Using bootstrapWithDefaults"
docker exec \$API_CONTAINER sh -c "cd /app && node -e '
const { bootstrapWithDefaults } = require(\"backend-lib/dist/bootstrap\");
bootstrapWithDefaults({
  workspaceName: \"$WORKSPACE_NAME\",
  workspaceDomain: \"$WORKSPACE_DOMAIN\",
  workspaceType: \"$WORKSPACE_TYPE\"
}).then(() => {
  console.log(\"Bootstrap successful\");
  process.exit(0);
}).catch(err => {
  console.error(\"Bootstrap failed:\", err);
  process.exit(1);
});
'" 2>&1 || echo "Bootstrap attempt 2 failed"

# Check if tables were created
echo -e "\n${YELLOW}Verifying database setup...${NC}"
POSTGRES_CONTAINER=\$(docker ps --format '{{.Names}}' | grep -E "postgres.*\${PROJECT_ID}" | head -1)
if [ ! -z "\$POSTGRES_CONTAINER" ]; then
    echo "Checking for created tables..."
    docker exec \$POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "\\dt" 2>&1 | head -20
    
    echo -e "\nChecking for workspaces..."
    docker exec \$POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c "SELECT id, name, type, domain FROM workspace;" 2>&1 || echo "No workspaces found"
fi

# Restart API and Dashboard to pick up changes
echo -e "\n${YELLOW}Restarting services...${NC}"
docker restart \$API_CONTAINER
DASHBOARD_CONTAINER=\$(docker ps --format '{{.Names}}' | grep -E "dashboard.*\${PROJECT_ID}" | head -1)
if [ ! -z "\$DASHBOARD_CONTAINER" ]; then
    docker restart \$DASHBOARD_CONTAINER
fi

echo -e "\n${GREEN}Bootstrap process completed!${NC}"
EOF

echo -e "\n${GREEN}===================================================${NC}"
echo -e "${GREEN}Bootstrap completed!${NC}"
echo -e "${GREEN}===================================================${NC}"
echo ""
echo "Next steps:"
echo "1. Check if tables were created in PostgreSQL"
echo "2. Verify workspace was created"
echo "3. Try accessing the dashboard"
echo "4. Check logs if issues persist"