# Coolify Deployment Guide for Dittofeed Multi-Tenant

## Overview
This guide covers two deployment options for Dittofeed multi-tenant on Coolify:
1. **Standard Multi-Tenant** - Basic multi-tenancy with OAuth
2. **Embedded Dashboard** - Multi-tenancy with iframe embedding and refresh tokens

## Deployment Options

### Option 1: Standard Multi-Tenant Deployment

#### Docker Compose File
```
Path: /docker-compose.coolify.yaml
```

#### Images Used
- API: `docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1`
- Dashboard: `docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1`
- Worker: `docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1`

#### Post-Deployment Command
```bash
#!/bin/bash
# Download and run standard bootstrap
curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/multi-tenant-main/deployment/bootstrap-standard-multitenant.sh | bash
```

#### Features
- ✅ Multi-tenant workspace isolation
- ✅ Google OAuth authentication
- ✅ HubSpot integration support
- ✅ Standard dashboard access
- ❌ No iframe embedding
- ❌ No refresh tokens

---

### Option 2: Embedded Dashboard Deployment

#### Docker Compose File
```
Path: /docker-compose.coolify-embedded.yaml
```

#### Images Used
- API: `aymensakka/dittofeed-api:embedded-final`
- Dashboard: `aymensakka/dittofeed-dashboard:embedded-final`
- Worker: `aymensakka/dittofeed-worker:embedded-final`

#### Post-Deployment Command
```bash
#!/bin/bash
# Download and run embedded bootstrap
curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/multi-tenant-main/deployment/bootstrap-embedded-dashboard.sh | bash
```

#### Features
- ✅ All standard multi-tenant features
- ✅ Iframe-embeddable dashboard
- ✅ JWT with refresh tokens (15-min access, 7-day refresh)
- ✅ Token rotation with reuse detection
- ✅ Session auditing
- ✅ Rate limiting

---

## Environment Variables (Both Deployments)

### Required Variables
```bash
# Core Configuration
NODE_ENV=production
AUTH_MODE=multi-tenant
AUTH_PROVIDER=google

# Security (generate with: openssl rand -base64 32)
JWT_SECRET=<secure-random-string>
SECRET_KEY=<secure-random-string>
NEXTAUTH_SECRET=<secure-random-string>

# Google OAuth
GOOGLE_CLIENT_ID=<your-google-client-id>
GOOGLE_CLIENT_SECRET=<your-google-client-secret>

# Database
POSTGRES_PASSWORD=<secure-password>
DATABASE_URL=postgresql://dittofeed:${POSTGRES_PASSWORD}@postgres:5432/dittofeed

# Services
REDIS_PASSWORD=<secure-password>
CLICKHOUSE_PASSWORD=<secure-password>
CLICKHOUSE_USER=dittofeed

# URLs (adjust for your domain)
NEXTAUTH_URL=https://your-dashboard.com/dashboard
NEXT_PUBLIC_API_BASE=https://your-api.com
API_BASE_URL=https://your-api.com
DASHBOARD_URL=https://your-dashboard.com

# Multi-tenancy
NEXT_PUBLIC_AUTH_MODE=multi-tenant
NEXT_PUBLIC_ENABLE_MULTITENANCY=true
WORKSPACE_ISOLATION_ENABLED=true
ALLOW_AUTO_WORKSPACE_CREATION=true

# Bootstrap
BOOTSTRAP_WORKSPACE_NAME=your-workspace
BOOTSTRAP_WORKSPACE_ADMIN_EMAIL=admin@your-domain.com
```

### Optional Variables
```bash
# HubSpot Integration
HUBSPOT_CLIENT_ID=<hubspot-client-id>
HUBSPOT_CLIENT_SECRET=<hubspot-secret>

# Cloudflare Tunnel
CF_TUNNEL_TOKEN=<cloudflare-tunnel-token>
CF_TUNNEL_ID=<cloudflare-tunnel-id>

# Docker Registry (if using private registry)
DOCKER_REGISTRY_USERNAME=coolify-system
DOCKER_REGISTRY_PASSWORD=<registry-password>

# Embedded Dashboard Only
ENABLE_EMBEDDED_DASHBOARD=true
SESSION_TOKEN_TTL=900  # 15 minutes
REFRESH_TOKEN_TTL=604800  # 7 days
MAX_SESSIONS_PER_WORKSPACE=1000
```

---

## Pre-Deployment Command (Both)

```bash
#!/bin/bash
# Login to Docker registry if using private images
if [ ! -z "$DOCKER_REGISTRY_USERNAME" ]; then
    docker login docker.reactmotion.com \
        --username $DOCKER_REGISTRY_USERNAME \
        --password "$DOCKER_REGISTRY_PASSWORD"
fi
```

---

## Bootstrap Scripts Comparison

| Feature | Standard Multi-Tenant | Embedded Dashboard |
|---------|----------------------|-------------------|
| **Script** | `bootstrap-standard-multitenant.sh` | `bootstrap-embedded-dashboard.sh` |
| **Database Init Script** | `init-database-standard.sh` | `init-database-embedded.sh` |
| **Database Tables** | Core tables only | Core + Embedded session tables |
| **OAuth Setup** | Basic Google OAuth | OAuth with embedded support |
| **Session Management** | Standard cookies | JWT with refresh tokens |
| **API Endpoints** | `/api/*` only | `/api/*` + `/api-l/*` |
| **Dashboard Routes** | `/dashboard/*` only | `/dashboard/*` + `/dashboard-l/embedded/*` |
| **Health Checks** | Basic health endpoint | Health + embedded session endpoints |
| **Token Rotation** | No | Yes (with family detection) |
| **Audit Logging** | Basic | Enhanced with session audit |
| **Rate Limiting** | Basic | Advanced per-session limiting |

---

## Post-Deployment Verification

### For Standard Deployment
```bash
# SSH into server
ssh root@your-server

# Check services
docker ps

# Test endpoints
curl https://your-api.com/health
curl https://your-dashboard.com/dashboard

# Check logs
docker logs $(docker ps -q -f name=api)
```

### For Embedded Deployment
```bash
# SSH into server
ssh root@your-server

# Check services and embedded tables
docker exec $(docker ps -q -f name=postgres) psql -U dittofeed -d dittofeed -c "\dt *Embedded*"

# Test embedded endpoints
curl https://your-api.com/api-l/embedded-sessions/health
curl https://your-dashboard.com/dashboard-l/embedded/journeys

# Create test session
curl -X POST https://your-api.com/api-l/embedded-sessions/create \
  -H "Content-Type: application/json" \
  -d '{"workspaceId": "<workspace-id>"}'
```

---

## Troubleshooting

### Common Issues

#### 1. Bootstrap Script Fails
```bash
# Run manually on server
cd /
git clone https://github.com/aymensakka/dittofeed.git
cd dittofeed
git checkout multi-tenant-main

# For standard
./deployment/bootstrap-standard-multitenant.sh

# For embedded
./deployment/bootstrap-embedded-dashboard.sh
```

#### 2. Database Tables Missing
```bash
# Apply schema manually
docker exec $(docker ps -q -f name=api) sh -c \
  "npx drizzle-kit push:pg --config=packages/backend-lib/drizzle.config.ts"

# Or use init-database scripts
# For standard deployment:
./deployment/init-database-standard.sh

# For embedded deployment:
./deployment/init-database-embedded.sh
```

#### 3. Embedded Sessions Not Working
```bash
# Check tables exist
docker exec $(docker ps -q -f name=postgres) psql -U dittofeed -d dittofeed -c "
  SELECT table_name FROM information_schema.tables 
  WHERE table_name LIKE '%Embedded%';
"

# If missing, create manually
docker exec $(docker ps -q -f name=postgres) psql -U dittofeed -d dittofeed \
  -f /deployment/0020_embedded_sessions.sql
```

#### 4. OAuth Not Working
```bash
# Check AuthProvider table
docker exec $(docker ps -q -f name=postgres) psql -U dittofeed -d dittofeed -c "
  SELECT * FROM \"AuthProvider\";
"

# Verify environment variables
docker exec $(docker ps -q -f name=api) env | grep -E "GOOGLE|AUTH"
```

---

## Migration Between Deployments

### From Standard to Embedded

1. **Backup database**
```bash
docker exec $(docker ps -q -f name=postgres) \
  pg_dump -U dittofeed dittofeed > backup.sql
```

2. **Update Docker Compose in Coolify**
   - Change path to `/docker-compose.coolify-embedded.yaml`
   - Update image tags to `embedded-final`

3. **Run embedded bootstrap**
```bash
./deployment/bootstrap-embedded-dashboard.sh
```

4. **Verify new tables**
```bash
docker exec $(docker ps -q -f name=postgres) psql -U dittofeed -d dittofeed -c "\dt *Embedded*"
```

### From Embedded to Standard

1. **Note**: You'll lose embedded features but data remains intact
2. **Update Docker Compose in Coolify**
   - Change path to `/docker-compose.coolify.yaml`
   - Update image tags to `multitenancy-redis-v1`
3. **Redeploy** (embedded tables remain but unused)

---

## Cron Jobs (Both Deployments)

Add to server crontab:
```bash
sudo crontab -e

# Add these lines:
# Update Cloudflare tunnel IPs after container restarts
*/5 * * * * /root/dittofeed/deployment/update-cf-from-host.sh

# Clean up old embedded sessions (embedded deployment only)
0 */6 * * * docker exec $(docker ps -q -f name=postgres) psql -U dittofeed -d dittofeed -c "DELETE FROM \"EmbeddedSession\" WHERE \"expiresAt\" < NOW() - INTERVAL '7 days';"
```

---

## Quick Decision Guide

**Choose Standard Multi-Tenant if:**
- You only need basic multi-tenancy
- No iframe embedding required
- Standard session management is sufficient
- Simpler deployment preferred

**Choose Embedded Dashboard if:**
- You need iframe embedding
- Refresh token support required
- Enhanced security with token rotation
- Session auditing needed
- Building a platform that embeds Dittofeed

---

## Support Resources

- **Documentation**: [BOOTSTRAP.md](./BOOTSTRAP.md)
- **Fork Management**: [FORK_MANAGEMENT_GUIDE.md](../FORK_MANAGEMENT_GUIDE.md)
- **Embedded Guide**: [EMBEDDED_DASHBOARD_GUIDE.md](../EMBEDDED_DASHBOARD_GUIDE.md)
- **GitHub Issues**: https://github.com/aymensakka/dittofeed/issues

---

*Last Updated: 2025-08-24*