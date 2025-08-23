#!/bin/bash

# ==============================================================================
# Local Multi-Tenant Dittofeed Setup for Mac
# This script sets up a complete local development environment
# ==============================================================================

set -e

echo "===================================================="
echo "Local Multi-Tenant Dittofeed Setup"
echo "===================================================="
echo ""

# Configuration
LOCAL_DOMAIN="localhost"
API_PORT=3001
DASHBOARD_PORT=3000
POSTGRES_PORT=5433  # Changed to avoid conflict with Supabase
REDIS_PORT=6380     # Changed to avoid conflicts
CLICKHOUSE_PORT=8124  # Changed to avoid conflicts
TEMPORAL_PORT=7234    # Changed to avoid conflicts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ==============================================================================
# STEP 1: Check Prerequisites
# ==============================================================================
echo -e "${YELLOW}Step 1: Checking prerequisites...${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker Desktop.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Docker is running${NC}"

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Node.js $(node -v) is installed${NC}"

# Check if Yarn is installed
if ! command -v yarn &> /dev/null; then
    echo -e "${YELLOW}⚠️  Yarn not found. Installing...${NC}"
    npm install -g yarn
fi
echo -e "${GREEN}✅ Yarn $(yarn -v) is installed${NC}"

# ==============================================================================
# STEP 2: Create Docker Compose for Local Development
# ==============================================================================
echo ""
echo -e "${YELLOW}Step 2: Creating Docker Compose configuration...${NC}"

cat > docker-compose.local.yml << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:14
    container_name: dittofeed-postgres
    environment:
      POSTGRES_USER: dittofeed
      POSTGRES_PASSWORD: password
      POSTGRES_DB: dittofeed
    ports:
      - "5433:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dittofeed"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7
    container_name: dittofeed-redis
    ports:
      - "6380:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  clickhouse:
    image: clickhouse/clickhouse-server:23.3
    container_name: dittofeed-clickhouse
    environment:
      CLICKHOUSE_DB: dittofeed
      CLICKHOUSE_USER: dittofeed
      CLICKHOUSE_PASSWORD: password
      CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT: 1
    ports:
      - "8124:8123"
      - "9001:9000"
    volumes:
      - clickhouse_data:/var/lib/clickhouse
    healthcheck:
      test: ["CMD", "clickhouse-client", "--query", "SELECT 1"]
      interval: 10s
      timeout: 5s
      retries: 5

  temporal:
    image: temporalio/auto-setup:1.22
    container_name: dittofeed-temporal
    depends_on:
      - postgres
    environment:
      - DB=postgresql
      - DB_PORT=5432
      - POSTGRES_USER=dittofeed
      - POSTGRES_PWD=password
      - POSTGRES_SEEDS=postgres
    ports:
      - "7234:7233"
    healthcheck:
      test: ["CMD", "temporal", "workflow", "list"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
  clickhouse_data:
EOF

echo -e "${GREEN}✅ Docker Compose configuration created${NC}"

# ==============================================================================
# STEP 3: Start Infrastructure Services
# ==============================================================================
echo ""
echo -e "${YELLOW}Step 3: Starting infrastructure services...${NC}"

docker-compose -f docker-compose.local.yml up -d postgres redis clickhouse temporal

# Wait for services to be healthy
echo "Waiting for services to be ready..."
for i in {1..30}; do
    if docker exec dittofeed-postgres pg_isready -U dittofeed > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PostgreSQL is ready${NC}"
        break
    fi
    echo -n "."
    sleep 2
done

# ==============================================================================
# STEP 4: Create Environment Files
# ==============================================================================
echo ""
echo -e "${YELLOW}Step 4: Creating environment files...${NC}"

# Create .env for root
cat > .env << EOF
# Multi-tenant configuration
AUTH_MODE=multi-tenant
NEXT_PUBLIC_AUTH_MODE=multi-tenant
BOOTSTRAP=false

# Database
DATABASE_URL=postgresql://dittofeed:password@localhost:5433/dittofeed
DATABASE_HOST=localhost
DATABASE_PORT=5433
DATABASE_USER=dittofeed
DATABASE_PASSWORD=password
DATABASE_NAME=dittofeed

# Redis
REDIS_HOST=localhost
REDIS_PORT=6380

# ClickHouse
CLICKHOUSE_HOST=localhost
CLICKHOUSE_PORT=8124
CLICKHOUSE_USER=dittofeed
CLICKHOUSE_PASSWORD=password

# Temporal
TEMPORAL_ADDRESS=localhost:7234

# API Configuration
API_HOST=localhost
API_PORT=3001
NODE_ENV=development

# Dashboard Configuration
DASHBOARD_HOST=localhost
DASHBOARD_PORT=3000

# Google OAuth (you'll need to add your own)
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret

# NextAuth Configuration
NEXTAUTH_URL=http://localhost:3000/dashboard
NEXTAUTH_SECRET=$(openssl rand -base64 32)

# JWT Secret
JWT_SECRET=$(openssl rand -base64 32)
EOF

# Create .env for API
cp .env packages/api/.env

# Create .env for Dashboard
cat > packages/dashboard/.env.local << EOF
AUTH_MODE=multi-tenant
NEXT_PUBLIC_AUTH_MODE=multi-tenant
NEXT_PUBLIC_API_BASE=http://localhost:3001
NEXT_PUBLIC_ENABLE_MULTITENANCY=true
NEXTAUTH_URL=http://localhost:3000/dashboard
NEXTAUTH_SECRET=$(grep NEXTAUTH_SECRET .env | cut -d= -f2)
GOOGLE_CLIENT_ID=$(grep GOOGLE_CLIENT_ID .env | cut -d= -f2)
GOOGLE_CLIENT_SECRET=$(grep GOOGLE_CLIENT_SECRET .env | cut -d= -f2)
EOF

echo -e "${GREEN}✅ Environment files created${NC}"

# ==============================================================================
# STEP 5: Install Dependencies and Build
# ==============================================================================
echo ""
echo -e "${YELLOW}Step 5: Installing dependencies and building packages...${NC}"

# Install dependencies
yarn install

# Build packages in order
echo "Building isomorphic-lib..."
yarn workspace isomorphic-lib build

echo "Building backend-lib..."
yarn workspace backend-lib build

echo "Building emailo..."
yarn workspace emailo build

echo -e "${GREEN}✅ Dependencies installed and packages built${NC}"

# ==============================================================================
# STEP 6: Run Database Migrations
# ==============================================================================
echo ""
echo -e "${YELLOW}Step 6: Running database migrations...${NC}"

cd packages/backend-lib
yarn db:migrate
cd ../..

echo -e "${GREEN}✅ Database migrations completed${NC}"

# ==============================================================================
# STEP 7: Initialize Database for Multi-Tenant
# ==============================================================================
echo ""
echo -e "${YELLOW}Step 7: Initializing database for multi-tenant...${NC}"

# Create bootstrap script
cat > init-multitenant-db.js << 'EOF'
const { Client } = require('pg');

async function initDatabase() {
  const client = new Client({
    connectionString: process.env.DATABASE_URL
  });

  try {
    await client.connect();
    
    // Add multi-tenant columns if missing
    await client.query(`
      ALTER TABLE "Workspace" ADD COLUMN IF NOT EXISTS domain TEXT;
      ALTER TABLE "Workspace" ADD COLUMN IF NOT EXISTS "externalId" TEXT;
      ALTER TABLE "Workspace" ADD COLUMN IF NOT EXISTS "parentWorkspaceId" UUID REFERENCES "Workspace"(id);
    `);
    
    await client.query(`
      ALTER TABLE "WorkspaceMemberRole" ADD COLUMN IF NOT EXISTS "resourceType" TEXT;
    `);
    
    // Create default workspace
    const workspaceResult = await client.query(`
      INSERT INTO "Workspace" (id, name, type, status, domain, "createdAt", "updatedAt")
      VALUES (gen_random_uuid(), 'localhost', 'Root', 'Active', 'localhost', NOW(), NOW())
      ON CONFLICT (name) DO UPDATE SET domain = EXCLUDED.domain
      RETURNING id;
    `);
    
    const workspaceId = workspaceResult.rows[0].id;
    console.log('Workspace created with ID:', workspaceId);
    
    // Fix AuthProvider table if needed
    await client.query(`
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'AuthProvider' AND column_name = 'provider') THEN
          ALTER TABLE "AuthProvider" RENAME COLUMN provider TO type;
        END IF;
      END$$;
    `);
    
    // Setup OAuth provider
    await client.query(`
      DELETE FROM "AuthProvider" WHERE "workspaceId" = $1;
      
      INSERT INTO "AuthProvider" (
        "workspaceId", "type", "enabled", "config", "createdAt", "updatedAt"
      ) VALUES (
        $1, 'google', true, 
        '{"provider": "google", "scope": ["openid", "email", "profile"]}',
        NOW(), NOW()
      );
    `, [workspaceId]);
    
    console.log('✅ Database initialized for multi-tenant mode');
    console.log('✅ OAuth provider configured');
    
  } catch (err) {
    console.error('Error initializing database:', err);
  } finally {
    await client.end();
  }
}

initDatabase();
EOF

DATABASE_URL=postgresql://dittofeed:password@localhost:5433/dittofeed node init-multitenant-db.js

echo -e "${GREEN}✅ Database initialized for multi-tenant${NC}"

# ==============================================================================
# STEP 8: Create Start Scripts
# ==============================================================================
echo ""
echo -e "${YELLOW}Step 8: Creating start scripts...${NC}"

# Create API start script
cat > start-api.sh << 'EOF'
#!/bin/bash
cd packages/api
AUTH_MODE=multi-tenant yarn dev
EOF
chmod +x start-api.sh

# Create Dashboard start script
cat > start-dashboard.sh << 'EOF'
#!/bin/bash
cd packages/dashboard
AUTH_MODE=multi-tenant NEXT_PUBLIC_AUTH_MODE=multi-tenant yarn dev
EOF
chmod +x start-dashboard.sh

# Create Worker start script
cat > start-worker.sh << 'EOF'
#!/bin/bash
cd packages/worker
AUTH_MODE=multi-tenant yarn dev
EOF
chmod +x start-worker.sh

echo -e "${GREEN}✅ Start scripts created${NC}"

# ==============================================================================
# SUMMARY
# ==============================================================================
echo ""
echo "===================================================="
echo -e "${GREEN}Local Multi-Tenant Setup Complete!${NC}"
echo "===================================================="
echo ""
echo "Infrastructure services running:"
echo "  - PostgreSQL: localhost:5433"
echo "  - Redis: localhost:6380"
echo "  - ClickHouse: localhost:8124"
echo "  - Temporal: localhost:7234"
echo ""
echo "To start the application:"
echo "  1. In terminal 1: ./start-api.sh"
echo "  2. In terminal 2: ./start-dashboard.sh"
echo "  3. In terminal 3: ./start-worker.sh"
echo ""
echo "Access the application at:"
echo "  Dashboard: http://localhost:3000/dashboard"
echo "  API: http://localhost:3001"
echo ""
echo -e "${YELLOW}⚠️  Important: Add your Google OAuth credentials to .env${NC}"
echo ""
echo "To stop infrastructure services:"
echo "  docker-compose -f docker-compose.local.yml down"
echo ""
echo "To view logs:"
echo "  docker-compose -f docker-compose.local.yml logs -f [service-name]"
echo "===================================================="