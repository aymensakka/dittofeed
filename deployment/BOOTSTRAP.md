# Dittofeed Multi-Tenant Bootstrap Documentation

## Overview
This document details all bootstrap and initialization scripts for the Dittofeed multi-tenant deployment with embedded dashboard support. These scripts orchestrate database initialization, service deployment, and environment configuration.

## Main Orchestration Scripts

### Coolify Deployment Bootstrap Scripts

#### `bootstrap-standard-multitenant.sh` - Standard Multi-Tenant Bootstrap
**Purpose**: Bootstrap script for standard multi-tenant deployment using registry images.

**Usage in Coolify**:
```bash
# Post-deployment command:
curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/multi-tenant-main/deployment/bootstrap-standard-multitenant.sh | bash
```

**Features**:
- Uses `docker-compose.coolify.yaml`
- Registry images (`multitenancy-redis-v1`)
- Basic OAuth setup
- Standard dashboard access
- No embedded features

#### `bootstrap-embedded-dashboard.sh` - Embedded Dashboard Bootstrap
**Purpose**: Bootstrap script for embedded dashboard deployment with JWT and refresh tokens.

**Usage in Coolify**:
```bash
# Post-deployment command:
curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/multi-tenant-main/deployment/bootstrap-embedded-dashboard.sh | bash
```

**Features**:
- Uses `docker-compose.coolify-embedded.yaml`
- Embedded-final images
- Creates embedded session tables
- JWT with refresh tokens (15-min access, 7-day refresh)
- Token rotation and audit logging
- Iframe embedding support

### Manual Bootstrap Scripts

#### 1. `init-database.sh` - Complete Database Initialization
**Purpose**: The ultimate database bootstrap script that manually creates all required schema without relying on migrations.

**Key Features**:
- Creates all database tables with proper SQL DDL
- Includes multi-tenancy tables (Workspace, WorkspaceMember, WorkspaceMemberRole)
- Sets up OAuth/authentication tables (AuthProvider, WorkspaceMembeAccount)
- Creates embedded session tables for iframe support with refresh tokens
- Applies all foreign key constraints and indexes
- Runs bootstrap.js to populate initial data
- Tests endpoints after initialization

**Tables Created**:
- **Multi-tenancy**: `Workspace`, `WorkspaceMember`, `WorkspaceMemberRole`, `WorkspaceOccupantSetting`
- **Authentication**: `AuthProvider`, `WorkspaceMembeAccount`, `AdminApiKey`
- **Embedded Sessions**: `EmbeddedSession`, `EmbeddedSessionAudit`, `EmbeddedSessionRateLimit`
- **Core Dittofeed**: `Segment`, `Journey`, `MessageTemplate`, `UserProperty`, `ComputedProperty`, `SubscriptionGroup`
- **Email**: `EmailProvider`, `DefaultEmailProvider`
- **Security**: `Secret`, `WriteKey`

**Usage**:
```bash
./deployment/init-database.sh
```

### 2. `deploy-coolify-embedded.sh` - Production Deployment Orchestrator
**Purpose**: Main deployment script for Coolify/production environments using pre-built Docker images.

**Workflow**:
1. Checks environment configuration (.env file)
2. Verifies required environment variables (JWT_SECRET, Google OAuth credentials)
3. Checks if Docker images exist locally (embedded-final tagged)
4. Stops existing containers
5. Starts all services via docker-compose
6. Runs database migrations using Drizzle Kit
7. Validates service health

**Migration Command**:
```bash
docker-compose -f docker-compose.coolify-embedded.yaml exec -T api \
  npx drizzle-kit push:pg --config=drizzle.config.ts
```

**Required Images**:
- `aymensakka/dittofeed-api:embedded-final`
- `aymensakka/dittofeed-dashboard:embedded-final`
- `aymensakka/dittofeed-worker:embedded-final`

### 3. `local-multitenant-setup.sh` - Complete Local Development Setup
**Purpose**: Sets up a complete local development environment from scratch.

**Features**:
- Creates Docker Compose configuration for infrastructure
- Starts PostgreSQL, Redis, ClickHouse, and Temporal
- Generates environment files with secure secrets
- Installs Node dependencies
- Builds all packages in correct order
- Runs database migrations
- Creates initial workspace and OAuth configuration
- Generates start scripts for each service

**Services Configured**:
- PostgreSQL on port 5433
- Redis on port 6380
- ClickHouse on port 8124
- Temporal on port 7234
- API on port 3001
- Dashboard on port 3000

### 4. `fix-all.sh` - Comprehensive Fix Orchestrator
**Purpose**: Wrapper script that orchestrates other bootstrap scripts to fix deployment issues.

**Workflow**:
1. Runs `bootstrap-simple.sh` to check current status
2. Determines if workspace needs creation
3. Identifies if services need network fixes
4. Calls appropriate fix scripts based on detected issues

## Supporting Scripts

### `bootstrap-simple.sh`
- Quick status check of current deployment
- Reports workspace existence
- Checks service health
- Used by fix-all.sh for diagnostics

### `manual-bootstrap.sh`
- Manual workspace and data initialization
- Creates workspaces programmatically
- Sets up OAuth providers
- Initializes admin users

### `bootstrap-with-network-fix.sh`
- Handles network-related issues in deployments
- Fixes connectivity between services
- Resolves DNS and routing problems

## Database Migration Approaches

### 1. Drizzle Kit Migration (Recommended)
**Location**: `packages/backend-lib/drizzle/`

**Command**:
```bash
# From API container
npx drizzle-kit push:pg --config=drizzle.config.ts

# From host with DATABASE_URL
DATABASE_URL=postgresql://user:pass@host:port/db \
  npx drizzle-kit push:pg --config=drizzle.config.ts
```

**Configuration**: `packages/backend-lib/drizzle.config.ts`

### 2. Manual SQL Application
**Location**: `deployment/init-database.sh`

**Advantages**:
- Complete control over schema
- Works when Drizzle migrations fail
- Includes all tables in single transaction
- Can be run directly on database

### 3. Embedded Sessions Schema
**Location**: `packages/backend-lib/drizzle/0020_embedded_sessions.sql`

**Tables**:
- `EmbeddedSession`: Main session tracking with refresh tokens
- `EmbeddedSessionAudit`: Audit logging for security
- `EmbeddedSessionRateLimit`: Rate limiting for API protection

**Security Features**:
- Refresh token families for detecting token reuse
- Access token rotation with grace period
- Browser fingerprinting
- IP address tracking
- Comprehensive audit logging

## Environment Configuration

### Required Environment Variables
```bash
# Security
JWT_SECRET=<base64-encoded-secret>
SECRET_KEY=<session-secret>
NEXTAUTH_SECRET=<nextauth-secret>

# OAuth (Google)
GOOGLE_CLIENT_ID=<google-oauth-client-id>
GOOGLE_CLIENT_SECRET=<google-oauth-secret>

# Database
DATABASE_URL=postgresql://user:pass@host:port/db
POSTGRES_PASSWORD=<password>

# Redis
REDIS_PASSWORD=<password>

# ClickHouse
CLICKHOUSE_PASSWORD=<password>

# Multi-tenancy
AUTH_MODE=multi-tenant
NEXT_PUBLIC_AUTH_MODE=multi-tenant
NEXT_PUBLIC_ENABLE_MULTITENANCY=true
ALLOW_AUTO_WORKSPACE_CREATION=true

# URLs
NEXTAUTH_URL=https://your-domain.com/dashboard
NEXT_PUBLIC_API_BASE=https://your-domain.com:3001
```

### Optional Environment Variables
```bash
# HubSpot Integration
HUBSPOT_CLIENT_ID=<hubspot-client-id>
HUBSPOT_CLIENT_SECRET=<hubspot-secret>

# Worker Configuration
WORKER_REPLICAS=1
WORKER_CONCURRENCY=10
```

## Docker Compose Files

### `docker-compose.coolify-embedded.yaml`
- Production deployment configuration
- Uses embedded-final tagged images
- Includes health checks for all services
- Configures networking and volumes

### `docker-compose.coolify.yaml`
- Original Coolify deployment
- Uses registry images
- Includes Cloudflare tunnel

### `docker-compose.local.yml`
- Local development configuration
- Minimal infrastructure setup
- Used by local-multitenant-setup.sh

## Health Checks

### Fixed Health Check Configuration
All health checks now use Node.js instead of curl to avoid missing binary issues:

**API Health Check**:
```yaml
healthcheck:
  test: ["CMD", "node", "-e", "require('http').get('http://localhost:3001/api/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)}).on('error', () => process.exit(1))"]
```

**Dashboard Health Check**:
```yaml
healthcheck:
  test: ["CMD", "node", "-e", "require('http').get('http://localhost:3000/dashboard', (r) => {process.exit(r.statusCode === 200 || r.statusCode === 302 ? 0 : 1)}).on('error', () => process.exit(1))"]
```

## Bootstrap Order of Operations

### Complete Setup Sequence:
1. **Infrastructure Setup**
   - Start PostgreSQL, Redis, ClickHouse, Temporal
   - Wait for health checks to pass

2. **Database Initialization**
   - Create database schema (via init-database.sh or Drizzle)
   - Apply all migrations including embedded sessions
   - Create indexes and constraints

3. **Multi-Tenant Configuration**
   - Create root workspace
   - Set up OAuth providers
   - Configure workspace isolation

4. **Service Deployment**
   - Start API service
   - Run database migrations if needed
   - Start Dashboard service
   - Start Worker service(s)

5. **Validation**
   - Test API endpoints
   - Verify dashboard access
   - Check OAuth flow

## Troubleshooting

### Common Issues and Solutions

#### 1. API Container Unhealthy
**Cause**: curl not found in container for health check
**Solution**: Use Node.js-based health checks (implemented in latest docker-compose)

#### 2. Database Schema Missing
**Cause**: Migrations not run or failed
**Solution**: Run init-database.sh for manual schema creation

#### 3. OAuth Not Working
**Cause**: Missing or incorrect OAuth credentials
**Solution**: Verify GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .env

#### 4. Workspace Not Found
**Cause**: Bootstrap not completed
**Solution**: Run manual-bootstrap.sh or init-database.sh

#### 5. Services Can't Connect
**Cause**: Network configuration issues
**Solution**: Run bootstrap-with-network-fix.sh

## Quick Start Commands

### For Coolify Production Deployment:

#### Standard Multi-Tenant:
```bash
# In Coolify UI:
# 1. Set Docker Compose Path: /docker-compose.coolify.yaml
# 2. Add Post-deployment Command:
curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/multi-tenant-main/deployment/bootstrap-standard-multitenant.sh | bash
# 3. Configure environment variables (see COOLIFY_DEPLOYMENT_GUIDE.md)
# 4. Deploy
```

#### Embedded Dashboard:
```bash
# In Coolify UI:
# 1. Set Docker Compose Path: /docker-compose.coolify-embedded.yaml
# 2. Add Post-deployment Command:
curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/multi-tenant-main/deployment/bootstrap-embedded-dashboard.sh | bash
# 3. Configure environment variables (see COOLIFY_DEPLOYMENT_GUIDE.md)
# 4. Deploy
```

### For Local Development:
```bash
# Complete setup
./deployment/local-multitenant-setup.sh

# Start services
./start-api.sh
./start-dashboard.sh
./start-worker.sh
```

### For Fixing Issues:
```bash
# Comprehensive fix
./deployment/fix-all.sh

# Just database
./deployment/init-database.sh

# Just restart with fixed health checks
./restart-deployment.sh
```

## Key Findings

1. **init-database.sh is the master script** - Contains complete schema including embedded sessions
2. **Health checks must use Node.js** - curl is not available in production containers
3. **Migration options** - Drizzle Kit push or manual SQL application both work
4. **Embedded sessions require specific tables** - EmbeddedSession, Audit, and RateLimit tables
5. **Multi-tenancy requires workspace** - Must be created before users can authenticate
6. **OAuth configuration is critical** - Both API and Dashboard need matching OAuth credentials

## Notes

- All scripts are idempotent - safe to run multiple times
- Database schema includes proper indexes for performance
- Foreign key constraints ensure data integrity
- Row-level security can be enabled for additional isolation
- Embedded session tokens use refresh token families for security