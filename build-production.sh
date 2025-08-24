#!/bin/bash

# Production Build Script for Dittofeed Multi-tenant with Embedded Dashboard

set -e

echo "🚀 Building Dittofeed Multi-tenant Production..."

# Configuration
export NODE_ENV=production
export AUTH_MODE=multi-tenant

# Install dependencies
echo "📦 Installing dependencies..."
yarn install --frozen-lockfile

# Build backend libraries first
echo "🔨 Building backend-lib..."
cd packages/backend-lib
yarn build
cd ../..

echo "🔨 Building isomorphic-lib..."
cd packages/isomorphic-lib
yarn build
cd ../..

# Build API server
echo "🔨 Building API server..."
cd packages/api
yarn build
cd ../..

# Build Dashboard with embedded pages
echo "🔨 Building Dashboard with embedded pages..."
cd packages/dashboard

# Ensure embedded pages have correct extension
echo "📝 Checking embedded page extensions..."
for dir in src/pages/dashboard-l/embedded/*/; do
  if [ -d "$dir" ]; then
    for f in "$dir"*.tsx; do
      if [ -f "$f" ] && [[ ! "$f" == *.page.tsx ]]; then
        mv "$f" "${f%.tsx}.page.tsx"
      fi
    done
  fi
done

# Build Next.js
NEXT_PUBLIC_AUTH_MODE=multi-tenant \
NEXT_PUBLIC_ENABLE_MULTITENANCY=true \
yarn build

cd ../..

# Build Worker
echo "🔨 Building Worker..."
cd packages/worker
yarn build
cd ../..

# Generate Prisma client
echo "🔨 Generating Prisma client..."
cd packages/backend-lib
npx prisma generate
cd ../..

# Prepare production assets
echo "📦 Preparing production assets..."
mkdir -p dist

# Copy build outputs
cp -r packages/api/dist dist/api
cp -r packages/dashboard/.next dist/dashboard
cp -r packages/dashboard/public dist/dashboard-public
cp -r packages/worker/dist dist/worker

# Copy configuration files
cat > dist/env.production << 'EOF'
# Production Environment Configuration
AUTH_MODE=multi-tenant
NODE_ENV=production

# Database
DATABASE_URL=postgresql://dittofeed:password@db:5432/dittofeed

# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# ClickHouse
CLICKHOUSE_HOST=clickhouse
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=dittofeed
CLICKHOUSE_PASSWORD=password

# Temporal
TEMPORAL_ADDRESS=temporal:7233

# JWT Configuration (CHANGE IN PRODUCTION!)
JWT_SECRET=CHANGE_THIS_IN_PRODUCTION
SECRET_KEY=CHANGE_THIS_IN_PRODUCTION

# Dashboard
NEXTAUTH_URL=https://yourdomain.com/dashboard
NEXTAUTH_SECRET=CHANGE_THIS_IN_PRODUCTION

# Google OAuth (Optional)
# GOOGLE_CLIENT_ID=your-google-client-id
# GOOGLE_CLIENT_SECRET=your-google-client-secret

# HubSpot OAuth (Optional)
# HUBSPOT_CLIENT_ID=your-hubspot-client-id
# HUBSPOT_CLIENT_SECRET=your-hubspot-client-secret
EOF

# Create Docker Compose for production
cat > dist/docker-compose.production.yml << 'EOF'
version: '3.8'

services:
  db:
    image: postgres:14
    environment:
      POSTGRES_USER: dittofeed
      POSTGRES_PASSWORD: password
      POSTGRES_DB: dittofeed
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dittofeed"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  clickhouse:
    image: clickhouse/clickhouse-server:23.3
    environment:
      CLICKHOUSE_USER: dittofeed
      CLICKHOUSE_PASSWORD: password
    volumes:
      - clickhouse_data:/var/lib/clickhouse
    healthcheck:
      test: ["CMD", "clickhouse-client", "--query", "SELECT 1"]
      interval: 10s
      timeout: 5s
      retries: 5

  temporal:
    image: temporalio/auto-setup:1.22
    environment:
      - DB=postgresql
      - DB_PORT=5432
      - POSTGRES_USER=dittofeed
      - POSTGRES_PWD=password
      - POSTGRES_SEEDS=db
    depends_on:
      db:
        condition: service_healthy

  api:
    build:
      context: .
      dockerfile: Dockerfile.api
    env_file:
      - env.production
    ports:
      - "3001:3001"
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
      clickhouse:
        condition: service_healthy
    command: node api/index.js

  dashboard:
    build:
      context: .
      dockerfile: Dockerfile.dashboard
    env_file:
      - env.production
    ports:
      - "3000:3000"
    depends_on:
      - api
    command: node dashboard/server.js

  worker:
    build:
      context: .
      dockerfile: Dockerfile.worker
    env_file:
      - env.production
    depends_on:
      - temporal
      - db
      - redis
    command: node worker/index.js

volumes:
  postgres_data:
  clickhouse_data:
EOF

# Create Dockerfiles
cat > dist/Dockerfile.api << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY api/ ./api/
COPY package.json yarn.lock ./
RUN yarn install --production
EXPOSE 3001
CMD ["node", "api/index.js"]
EOF

cat > dist/Dockerfile.dashboard << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY dashboard/ ./dashboard/
COPY dashboard-public/ ./public/
COPY package.json yarn.lock ./
RUN yarn install --production
EXPOSE 3000
CMD ["yarn", "start"]
EOF

cat > dist/Dockerfile.worker << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY worker/ ./worker/
COPY package.json yarn.lock ./
RUN yarn install --production
CMD ["node", "worker/index.js"]
EOF

# Create deployment script
cat > dist/deploy.sh << 'EOF'
#!/bin/bash

echo "🚀 Deploying Dittofeed Multi-tenant..."

# Load environment
source env.production

# Bootstrap database
echo "📦 Bootstrapping database..."
docker-compose -f docker-compose.production.yml run --rm api node -e "
const { db } = require('./api/db');
const fs = require('fs');
const migration = fs.readFileSync('/migrations/embedded-sessions.sql', 'utf8');
db.raw(migration).then(() => {
  console.log('Database bootstrapped');
  process.exit(0);
}).catch(err => {
  console.error('Bootstrap failed:', err);
  process.exit(1);
});
"

# Start services
echo "🎯 Starting services..."
docker-compose -f docker-compose.production.yml up -d

echo "✨ Deployment complete!"
echo "Dashboard: http://localhost:3000"
echo "API: http://localhost:3001"
EOF

chmod +x dist/deploy.sh

echo "✨ Build complete!"
echo ""
echo "Production build artifacts are in the 'dist' directory."
echo "To deploy:"
echo "  1. Copy the 'dist' directory to your production server"
echo "  2. Update env.production with your production configuration"
echo "  3. Run: ./deploy.sh"
echo ""
echo "For embedded dashboard integration:"
echo "  - API endpoints: https://yourdomain.com/api-l/embedded-sessions/*"
echo "  - Dashboard pages: https://yourdomain.com/dashboard-l/embedded/*"
echo "  - See EMBEDDED_DASHBOARD_GUIDE.md for integration details"