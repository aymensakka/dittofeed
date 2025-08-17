# Database Initialization Fix

## Root Cause
Migration files in `packages/backend-lib/drizzle/` are not included in the production Docker images, preventing database initialization.

## Solution Options

### Option 1: Fix Docker Images (Recommended)
Update Dockerfiles to include migration files:

#### packages/api/Dockerfile
Add after line copying backend-lib:
```dockerfile
COPY ./packages/backend-lib/drizzle ./packages/backend-lib/drizzle
```

#### packages/worker/Dockerfile
Add similar line to include migrations.

### Option 2: Manual Database Initialization
Create initialization script that runs migrations manually:

```bash
#!/bin/bash
# fix-database-init.sh

# For local deployment
docker exec -it dittofeed_postgres psql -U dittofeed -d dittofeed < migration.sql

# For Coolify deployment
docker exec -it $(docker ps | grep postgres | awk '{print $1}') \
  psql -U dittofeed -d dittofeed < migration.sql
```

### Option 3: Mount Migrations as Volume
In docker-compose.yaml:
```yaml
api:
  volumes:
    - ./packages/backend-lib/drizzle:/service/packages/backend-lib/drizzle:ro
```

## Immediate Fix for Current Deployment

### Step 1: Create Combined Migration File
Combine all migration files into one:
```bash
cat packages/backend-lib/drizzle/*.sql > deployment/init-database.sql
```

### Step 2: Apply to Database
```bash
# Local
docker exec -i dittofeed_postgres psql -U dittofeed -d dittofeed < deployment/init-database.sql

# Production (Coolify)
docker exec -i $(docker ps | grep postgres | awk '{print $1}') \
  psql -U dittofeed -d dittofeed < deployment/init-database.sql
```

## Verification Steps
1. Check tables exist:
```sql
\dt
```

2. Verify core tables:
- workspaces
- workspace_members  
- users
- segments
- journeys
- templates

3. Test API:
```bash
curl http://localhost:3001/api
# Should return proper version
```

## Long-term Fix
1. Update Dockerfiles to include migrations
2. Ensure bootstrap code executes migrations
3. Add health check that verifies database schema
4. Add logging for bootstrap process
5. Consider using database migration tool like Drizzle Kit in production

## Environment Variables Required
```env
# These must be set for bootstrap to work
BOOTSTRAP=true
BOOTSTRAP_SAFE=true
BOOTSTRAP_WORKSPACE_NAME=Default
BOOTSTRAP_WORKSPACE_ADMIN_EMAIL=admin@example.com

# Required for multi-tenant
AUTH_MODE=multi-tenant
MULTITENANCY_ENABLED=true
WORKSPACE_ISOLATION_ENABLED=true
```

## Testing Bootstrap Locally
```bash
# Run migrations manually first
cd packages/backend-lib
DATABASE_URL=postgresql://dittofeed:localpass@localhost:5433/dittofeed \
  yarn drizzle-kit push:pg

# Then restart API
docker restart dittofeed_api
```

## Coolify Deployment Fix
1. SSH into Coolify server
2. Copy migration files to server
3. Run migrations against PostgreSQL container
4. Restart API and Worker containers
5. Verify tables and test endpoints

This fix addresses the immediate issue while providing a path for permanent resolution.