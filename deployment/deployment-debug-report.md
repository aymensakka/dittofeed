# Dittofeed Multitenancy Deployment Debug Report

## Deployment Overview

### Current Status Summary
- **Deployment Platform**: Coolify
- **Domain Configuration**: 
  - API: `https://communication-api.caramelme.com`
  - Dashboard: `https://communication-dashboard.caramelme.com`
- **Auth Mode**: Multi-tenant with Google OAuth
- **Tunnel Provider**: Cloudflare Zero Trust

## Known Issues & Solutions

### 1. Database Not Initialized ❌
**Problem**: PostgreSQL database exists but has no tables
- Error: "Did not find any relations"
- Dashboard shows: "Misconfigured auth provider, missing"
- API returns empty version: `{"version":""}`

**Root Cause**: Bootstrap process not creating schema despite BOOTSTRAP=true

**Solution**: Run manual database initialization
```bash
./init-database.sh
```

### 2. Container Health Status ⚠️
**Current Container States**:
- `api-*`: Unhealthy (but responding)
- `dashboard-*`: Unhealthy (but running)
- `worker-*`: Restarting (Temporal not deployed)
- `postgres-*`: Healthy
- `redis-*`: Healthy
- `cloudflared-*`: Running

### 3. Cloudflare Tunnel Configuration ✅
**Status**: Working after IP-based routing
- Routes updated to use container IPs instead of service names
- DNS resolution issues bypassed

## Environment Variables Status

### API Container ✅
```
NODE_ENV=production
AUTH_MODE=multi-tenant
BOOTSTRAP=true
BOOTSTRAP_SAFE=true
BOOTSTRAP_WORKER=true
BOOTSTRAP_WORKSPACE_NAME=RMT
BOOTSTRAP_WORKSPACE_ADMIN_EMAIL=aymen@reactmotion.com
DATABASE_URL=postgresql://dittofeed:[CONFIGURED]@postgres:5432/dittofeed
MULTITENANCY_ENABLED=true
WORKSPACE_ISOLATION_ENABLED=true
```

### Dashboard Container ✅
```
NODE_ENV=production
AUTH_MODE=multi-tenant
GOOGLE_CLIENT_ID=[CONFIGURED]
GOOGLE_CLIENT_SECRET=[CONFIGURED]
NEXTAUTH_SECRET=[CONFIGURED]
NEXTAUTH_URL=https://communication-dashboard.caramelme.com
API_BASE_URL=http://api:3001
NEXT_PUBLIC_API_BASE_URL=https://communication-api.caramelme.com
```

## Deployment Challenges Encountered

### 1. Coolify-Specific Issues
- **Container Name Changes**: Each deployment creates new container names
- **Network Isolation**: Service names not preserved
- **Port Mapping**: Containers not exposed to host by default

### 2. Docker Registry Authentication
- **Issue**: Coolify's non-TTY environment breaks `docker login`
- **Solution**: Use `--password-stdin` flag in deployment scripts

### 3. Password Special Characters
- **Issue**: Special characters in passwords break URL parsing
- **Initial Password**: `AXRH+ft7pHxNF/aM2m6P0g==`
- **Solution**: Changed to alphanumeric: `LOpnL3wYIbWUBax4qXeR`

### 4. Subdomain Structure
- **Initial Plan**: `api.com.caramelme.com` (multi-level)
- **Issue**: Cloudflare tunnel doesn't handle well
- **Solution**: Changed to `communication-api.caramelme.com`

## Current Endpoint Status

| Endpoint | Expected | Actual | Status |
|----------|----------|---------|--------|
| API Health | 200 | 404 | ⚠️ No health endpoint |
| API Version | 200 | 200 | ✅ Returns empty version |
| Dashboard Root | 200 | 307→500 | ❌ Redirects then errors |
| Dashboard Login | 200 | 404 | ❌ Route not found |
| OAuth Callback | 200 | 404 | ❌ Not accessible |

## Required Actions

### Immediate (To Get Working)
1. **Initialize Database Schema**
   ```bash
   ./init-database.sh
   ```

2. **Verify Tables Created**
   ```bash
   docker exec $(docker ps | grep postgres | awk '{print $1}') psql -U dittofeed -d dittofeed -c "\dt"
   ```

3. **Restart Services**
   ```bash
   docker restart $(docker ps | grep -E "api-|dashboard-" | awk '{print $1}')
   ```

### Long-term Improvements
1. **Stable Container Names**: Configure Coolify to preserve service names
2. **Host Network Mode**: Expose services on host ports
3. **Automated IP Updates**: Script to update tunnel routes after deployment
4. **Health Endpoints**: Add proper health check endpoints

## Bootstrap Process Analysis

The bootstrap should:
1. Create database schema (enums, tables, indexes)
2. Create initial workspace using `BOOTSTRAP_WORKSPACE_NAME`
3. Add admin user with `BOOTSTRAP_WORKSPACE_ADMIN_EMAIL`
4. Set up default providers and templates

**Current Issue**: Bootstrap script runs but doesn't execute migrations

## File System Structure
```
/service/
├── packages/
│   ├── api/
│   │   └── dist/scripts/startServer.js ✅
│   ├── backend-lib/
│   │   └── dist/src/
│   │       ├── bootstrap.js ✅
│   │       └── migrate.js ✅
│   └── [other packages]
├── node_modules/ ✅
└── package.json ✅
```

## Missing Components
1. **Temporal Service**: Worker failing to connect (not critical)
2. **ClickHouse**: Analytics database (optional)
3. **Migration Files**: Not included in production image
4. **Database Schema**: Must be created manually

## Success Criteria
- [ ] Database has tables
- [ ] API returns proper version
- [ ] Dashboard loads without 500 error
- [ ] Google OAuth login works
- [ ] Can create workspace and login

## Debug Commands Reference

```bash
# Check container status
docker ps | grep -E "api|dashboard|postgres|redis|cloudflared"

# View database tables
docker exec $(docker ps | grep postgres | awk '{print $1}') psql -U dittofeed -d dittofeed -c "\dt"

# Check API logs
docker logs $(docker ps | grep "api-" | awk '{print $1}') --tail 50

# Test endpoints
curl https://communication-api.caramelme.com/api
curl -I https://communication-dashboard.caramelme.com/

# Check environment variables
docker exec $(docker ps | grep "api-" | awk '{print $1}') env | grep -E "BOOTSTRAP|DATABASE"
```

## Next Steps
1. Run `init-database.sh` to create schema
2. Verify tables exist
3. Test dashboard login
4. Configure email provider (AWS SES)
5. Create first campaign

---
*Report generated for Dittofeed multitenancy deployment on Coolify with Cloudflare tunnel integration*