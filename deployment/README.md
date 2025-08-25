# Deployment Scripts

This folder contains scripts for building and deploying Dittofeed Docker images to Nexus registry.

## Quick Start

### For Development/Building
```bash
# Clone repository
git clone https://github.com/aymensakka/dittofeed.git
cd dittofeed

# Setup build environment (run once)
sudo ./deployment/setup-build-environment.sh

# Build and push images (2 vCPU server)
./deployment/build-and-push-images.sh

# OR for powerful servers (4+ vCPU)
./deployment/build-datacenter.sh
```

### For Production Deployment (Coolify)

#### Option 1: Standard Multi-Tenant Deployment
```bash
# In Coolify:
# - Docker Compose Path: /docker-compose.coolify.yaml
# - Post-deployment Command:
curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/multi-tenant-main/deployment/bootstrap-standard-multitenant.sh | bash
```

#### Option 2: Embedded Dashboard Deployment
```bash
# In Coolify:
# - Docker Compose Path: /docker-compose.coolify-embedded.yaml
# - Post-deployment Command:
curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/multi-tenant-main/deployment/bootstrap-embedded-dashboard.sh | bash
```

#### Manual Bootstrap (if needed)
```bash
# SSH into server
cd ~/dittofeed

# For standard deployment
./deployment/bootstrap-standard-multitenant.sh

# For embedded deployment
./deployment/bootstrap-embedded-dashboard.sh

# For detailed information, see:
# - deployment/BOOTSTRAP.md
# - deployment/COOLIFY_DEPLOYMENT_GUIDE.md
```

#### Environment Variables (both deployments)
```bash
# Required in Coolify:
AUTH_MODE=multi-tenant
JWT_SECRET=<generate-with-openssl-rand-base64-32>
GOOGLE_CLIENT_ID=<your-google-client-id>
GOOGLE_CLIENT_SECRET=<your-google-client-secret>
NEXTAUTH_URL=https://your-dashboard.com/dashboard
NEXT_PUBLIC_API_BASE=https://your-api.com
```

## Script Quick Reference

| Script | Purpose | When to Use |
|--------|---------|-------------|
| **Build & Deploy Scripts** | | |
| `setup-build-environment.sh` | Install Docker, Node.js, Yarn | First time setup |
| `build-and-push-images.sh` | Build all services sequentially | Standard builds |
| `build-datacenter.sh` | Parallel high-speed build | 4+ vCPU servers |
| **Individual Build Scripts** | | |
| `build-api.sh` | Build and push API only | Update API service |
| `build-dashboard.sh` | Build and push Dashboard only | Update Dashboard |
| `build-worker.sh` | Build and push Worker only | Update Worker |
| **Bootstrap & Configuration** | | |
| `bootstrap-standard-multitenant.sh` | Bootstrap standard deployment | **Coolify standard deployment** |
| `bootstrap-embedded-dashboard.sh` | Bootstrap embedded deployment | **Coolify embedded deployment** |
| `init-database-standard.sh` | Database initialization (standard) | Manual database setup without embedded |
| `init-database-embedded.sh` | Database initialization (embedded) | Manual database setup with embedded tables |
| `deploy-coolify-embedded.sh` | Deploy with embedded dashboard | Local embedded deployment |
| `fix-all.sh` | Complete orchestration script | Run all fixes in sequence |
| `bootstrap-simple.sh` | Quick status check | Check deployment status |
| `manual-bootstrap.sh` | Interactive workspace creation | Create workspace manually |
| `bootstrap-with-network-fix.sh` | Complete network setup | Fix network issues, IP changes |
| `fix-database-schema.sh` | Fix database schema | Add missing columns for multi-tenant |
| **[BOOTSTRAP.md](./BOOTSTRAP.md)** | **Complete bootstrap documentation** | **Detailed reference** |
| **[COOLIFY_DEPLOYMENT_GUIDE.md](./COOLIFY_DEPLOYMENT_GUIDE.md)** | **Coolify deployment guide** | **Production deployment** |
| **Cloudflare Tunnel Management** | | |
| `update-cf-from-host.sh` | Update tunnel from host | After container IP changes |
| `debug-cloudflared.sh` | Debug cloudflared container | Troubleshoot tunnel issues |
| **Utility Scripts** | | |
| `check-images.sh` | Check image status | Verify builds |
| `check-duplicate-instances.sh` | Find duplicate containers | Debug container conflicts |
| `check-coolify-status.sh` | Check Coolify deployment | Verify deployment status |

## Scripts Overview

### setup-build-environment.sh

Sets up Ubuntu VPS with all required dependencies for building Dittofeed.

**What it installs:**
- Docker CE with buildx plugin
- Node.js 18.x
- Yarn package manager
- Build essentials
- Git

**Usage:**
```bash
# Option 1: Run from cloned repo
sudo ./deployment/setup-build-environment.sh

# Option 2: Run directly from GitHub
curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/main/deployment/setup-build-environment.sh | sudo bash
```

### build-and-push-images.sh

Standard build script for Dittofeed Docker images. Optimized for datacenter/VPS environments.

**Features:**
- Automatically pulls latest code from git
- Builds for linux/amd64 platform
- Sequential builds (suitable for 2 vCPU servers)
- Direct push without retries (assumes stable connection)
- Verifies successful push to registry

**Usage:**
```bash
cd dittofeed
./deployment/build-and-push-images.sh
```

### build-datacenter.sh

High-performance build script for powerful VPS/datacenter environments.

**Features:**
- Parallel builds for all services
- Optimized for 4+ vCPU servers
- Background build processes
- Consolidated status reporting

**Usage:**
```bash
cd dittofeed
./deployment/build-datacenter.sh
```

**Requirements:**
- 4+ vCPUs recommended
- 8GB+ RAM recommended
- Fast network connection

### push-single-image.sh

Utility script for pushing a single image with automatic retry.

**Usage:**
```bash
./deployment/push-single-image.sh docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1
```

**When to use:**
- When main build script push fails
- For retrying large image uploads
- Handling network timeout issues

### push-slow-connection.sh

Batch push script with automatic retry for all images.

**Usage:**
```bash
./deployment/push-slow-connection.sh
```

**Features:**
- Pushes all three services (api, dashboard, worker)
- Infinite retry with fast 2-second delays
- Handles timeouts and connection drops
- Progress tracking

## Choosing the Right Script

### For 2 vCPU servers (standard):
```bash
# Use the standard build script
./deployment/build-and-push-images.sh
```

### For 4+ vCPU servers (powerful):
```bash
# Use the parallel build script
./deployment/build-datacenter.sh
```

### For push issues:
```bash
# Retry a single image
./deployment/push-single-image.sh <image:tag>

# Or retry all images
./deployment/push-slow-connection.sh
```

## Complete Workflow Examples

### First Time Setup
```bash
# 1. Clone repository
git clone https://github.com/aymensakka/dittofeed.git
cd dittofeed

# 2. Install dependencies
sudo ./deployment/setup-build-environment.sh

# 3. Build and push (choose based on server specs)
# For 2 vCPU:
./deployment/build-and-push-images.sh

# For 4+ vCPU:
./deployment/build-datacenter.sh
```

### Subsequent Builds
```bash
cd dittofeed

# Pull latest and build
./deployment/build-and-push-images.sh

# Or for specific version
git checkout v1.2.3
./deployment/build-and-push-images.sh
```

### Handling Push Failures
```bash
# If push fails during build, retry just that image
./deployment/push-single-image.sh docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1

# Or retry all images
./deployment/push-slow-connection.sh
```

### What it does

1. Checks environment prerequisites
2. Logs into the Docker registry
3. Installs project dependencies
4. Builds each service (api, dashboard, worker) for linux/amd64
5. Pushes images to Nexus registry
6. Verifies the push was successful

### Images produced

- `docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1`
- `docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1`
- `docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1`

## Multi-Tenant Deployment with Coolify

### Prerequisites
- Coolify instance with Docker Compose deployment
- Cloudflare Zero Trust tunnel configured
- PostgreSQL, Redis, ClickHouse, Temporal services

### Bootstrap Process

The bootstrap scripts handle database initialization, workspace creation, OAuth setup, and optionally building the dashboard image with multi-tenant authentication.

#### OAuth Setup

For OAuth authentication with Google:

1. **Configure Google OAuth:**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create OAuth 2.0 credentials
   - Add authorized redirect URIs:
     - Local: `http://localhost:3001/api/public/auth/oauth2/callback/google`
     - Production: `https://your-api-domain.com/api/public/auth/oauth2/callback/google`

2. **Update Database Schema:**
   ```bash
   # For new installations (standard deployment)
   ./deployment/init-database-standard.sh
   
   # For new installations (embedded deployment)
   ./deployment/init-database-embedded.sh
   
   # For existing installations (migration)
   psql -U dittofeed -d dittofeed -f deployment/oauth-migration.sql
   ```

3. **Set Environment Variables:**
   ```bash
   # In Coolify or docker-compose.yml
   AUTH_MODE=multi-tenant
   AUTH_PROVIDER=google
   GOOGLE_CLIENT_ID=your-client-id
   GOOGLE_CLIENT_SECRET=your-client-secret
   JWT_SECRET=your-jwt-secret-min-32-chars
   SECRET_KEY=your-session-secret
   ```

4. **See detailed OAuth documentation:**
   - [OAuth Setup Guide](./OAUTH_SETUP.md) - Complete OAuth configuration guide
   - [OAuth Migration Script](./oauth-migration.sql) - Database migration for OAuth

#### Available Bootstrap Scripts

1. **manual-bootstrap.sh** - Main bootstrap script that handles:
   - Database initialization and schema updates
   - Workspace creation with multi-tenant support
   - OAuth provider setup (Google authentication)
   - Optional dashboard Docker image build with `--build-dashboard` flag
   
2. **build-dashboard-simple.sh** - Standalone script for just building and pushing the dashboard
   - Builds dashboard with AUTH_MODE=multi-tenant baked in
   - Includes all required environment variables
   - Pushes to Docker registry
   
3. **bootstrap-simple.sh** - Quick status check script
   - Shows container status
   - Displays workspace information
   - Checks database initialization

#### Usage Examples

**Complete bootstrap with dashboard build:**
```bash
# This will initialize database, create workspace, setup OAuth, AND build dashboard image
./deployment/manual-bootstrap.sh --build-dashboard
```

**Bootstrap without rebuilding dashboard:**
```bash
# Just initialize database, create workspace, and setup OAuth
./deployment/manual-bootstrap.sh
```

**Build and push dashboard only:**
```bash
# When you need to rebuild dashboard with updated AUTH_MODE
./deployment/build-dashboard-simple.sh
```

**Check deployment status:**
```bash
# Quick health check of all services
./deployment/bootstrap-simple.sh
```

2. **Fix Network Issues (after container restart):**
   ```bash
   # Fixes IP changes and updates internal networking
   ./deployment/bootstrap-with-network-fix.sh
   ```

### Cloudflare Tunnel Updates

Since Coolify recreates containers with new IPs on redeploy, the Cloudflare tunnel needs updating:

1. **Automatic Updates (Host Cron):**
   ```bash
   # Add to root crontab
   */5 * * * * /root/dittofeed/deployment/update-cf-from-host.sh
   ```

2. **Manual Update (after deployment):**
   ```bash
   cd ~/dittofeed
   ./deployment/update-cf-from-host.sh
   ```

3. **Debug Tunnel Issues:**
   ```bash
   ./deployment/debug-cloudflared.sh
   ./deployment/check-cloudflared-type.sh
   ```

### Environment Variables

Key environment variables for multi-tenant mode with OAuth:
- `AUTH_MODE=multi-tenant`
- `AUTH_PROVIDER=google`
- `NEXT_PUBLIC_AUTH_MODE=multi-tenant`
- `NEXT_PUBLIC_ENABLE_MULTITENANCY=true`
- `WORKSPACE_ISOLATION_ENABLED=true`
- `BOOTSTRAP_WORKSPACE_NAME=caramel`
- `DOMAIN=caramelme.com`

OAuth-specific variables:
- `GOOGLE_CLIENT_ID=your-google-client-id`
- `GOOGLE_CLIENT_SECRET=your-google-client-secret`
- `JWT_SECRET=your-jwt-secret-min-32-chars`
- `SECRET_KEY=your-session-secret-key`
- `NEXTAUTH_URL=https://communication-dashboard.caramelme.com/dashboard`
- `NEXTAUTH_SECRET=your-nextauth-secret`

### Common Multi-Tenant Issues

1. **OAuth Authentication Issues:**
   - **"Authentication failed" errors:**
     - Ensure user is in WorkspaceMember table with proper workspace association
     - Check WorkspaceMemberRole table has role for the user
     - Verify WorkspaceMembeAccount has OAuth provider ID
   - **"No organization" error:**
     - User is not assigned to any workspace
     - Admin must add user via permissions API or database
   - **Session persistence issues:**
     - Check JWT_SECRET and SECRET_KEY are set correctly
     - Verify cookie domain settings match deployment

2. **404 on Dashboard (All Routes):**
   - **Root Cause**: Conflicting redirect in next.config.js (two redirects for '/')
   - **Quick Fix**: Run `./deployment/quick-fix-remote-404.sh` on server
   - **Permanent Fix**: 
     ```bash
     # Apply the fix locally
     ./deployment/apply-dashboard-fix.sh
     # Rebuild dashboard image
     ./deployment/build-dashboard.sh
     # Redeploy in Coolify
     ```
   - **Other causes**:
     - Workspace name mismatch (check `BOOTSTRAP_WORKSPACE_NAME`)
     - Wrong auth mode (must be `multi-tenant`)
     - Run `manual-bootstrap.sh` to create workspace

3. **Bad Gateway After Redeploy:**
   - Container IPs changed
   - Run `update-cf-from-host.sh`
   - Check tunnel status with `debug-cloudflared.sh`

4. **Workspace Not Found:**
   ```sql
   -- Check workspace in database
   docker exec $(docker ps -q -f name=postgres) psql -U dittofeed -d dittofeed -c "SELECT name, domain FROM \"Workspace\";"
   ```

5. **OAuth Database Errors:**
   - **"null value in column providerAccountId":**
     - Run `oauth-migration.sql` to update schema
     - Seed proper OAuth data for existing users
   - **Missing OAuth tables:**
     - Run `init-database-standard.sh` or `init-database-embedded.sh` for fresh setup
     - Or run `oauth-migration.sql` for existing deployments

6. **Dashboard Returns 404 for All Routes:**
   - **Diagnosis**: Run `./deployment/diagnose-404.sh`
   - **Environment Check**: Verify `NEXT_PUBLIC_AUTH_MODE=multi-tenant`
   - **Next.js Config**: Check for conflicting redirects in next.config.js
   - **Solution**: Apply fix with `quick-fix-remote-404.sh` or rebuild image

## Troubleshooting
### Build individual images
# Build and push dashboard
docker build --platform linux/amd64 -f packages/dashboard/Dockerfile -t docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1 . && docker push docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1
 # Build and push worker
  docker build --platform linux/amd64 -f packages/worker/Dockerfile -t docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1 . && \ docker push docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1
 Or run them separately:

  For Dashboard:
  # Build
  docker build --platform linux/amd64 -f packages/dashboard/Dockerfile -t
  docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1 .

  # Push
  docker push docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1

  For Worker:
  # Build
  docker build --platform linux/amd64 -f packages/worker/Dockerfile -t
  docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1 .

  # Push
  docker push docker.reactmotion.com/my-docker-repo/dittofeed/worker:multitenancy-redis-v1

### Common Issues

1. **"yarn: command not found"**
   ```bash
   sudo npm install -g yarn
   # Or run the setup script:
   sudo ./deployment/setup-build-environment.sh
   ```

2. **"Cannot connect to Docker daemon"**
   ```bash
   sudo systemctl start docker
   sudo usermod -aG docker $USER
   # Logout and login again
   ```

3. **"no basic auth credentials" in Coolify**
   - Ensure Coolify has these environment variables set:
     - `DOCKER_REGISTRY_USERNAME=coolify-system`
     - `DOCKER_REGISTRY_PASSWORD=9sFPGGDJUFnE4z*z4Aj9`
   - Add pre-deployment command in Coolify:
     ```bash
     docker login docker.reactmotion.com --username coolify-system --password '9sFPGGDJUFnE4z*z4Aj9'
     ```

4. **"no matching manifest for linux/amd64"**
   - Images were built for wrong architecture
   - Run the build script on Ubuntu/Linux VPS (not Mac)

5. **Out of memory during build**
   - Script already handles this with sequential builds
   - If still failing, increase swap:
     ```bash
     sudo fallocate -l 4G /swapfile
     sudo chmod 600 /swapfile
     sudo mkswap /swapfile
     sudo swapon /swapfile
     ```

## Build Process Flow

1. **Setup Phase:**
   - Checks Linux environment
   - Verifies Docker, Node.js, Yarn installed
   - Shows system resources

2. **Update Phase:**
  cd dittofeed
  git fetch origin
  git reset --hard origin/main
  ./deployment/build-and-push-images.sh
   - Fetches latest code from GitHub
   - Resets to origin/main

3. **Build Phase:**
   - Logs into Docker registry
   - Builds each service sequentially:
     - API service
     - Dashboard service  
     - Worker service
   - Cleans Docker cache between builds

4. **Push Phase:**
   - Pushes each image to Nexus registry
   - Verifies successful upload

5. **Cleanup Phase:**
   - Logs out of Docker registry
   - Reports completion status

## Common Issues and Solutions

### Dashboard Returns 404 or 500 Error
**Cause:** Missing database columns or incorrect environment variables
**Solution:**
```bash
# Run the database schema fix
./deployment/fix-database-schema.sh

# Ensure these environment variables are set in Coolify:
NEXTAUTH_URL=https://communication-dashboard.caramelme.com/dashboard
CLICKHOUSE_HOST=clickhouse
CLICKHOUSE_USER=dittofeed
CLICKHOUSE_PASSWORD=password
NODE_ENV=production

# Restart dashboard container
docker restart $(docker ps -q -f name=dashboard)
```

### API Returns 502 Bad Gateway
**Cause:** API container not responding or IP changed
**Solution:**
```bash
# Run network fix
./deployment/bootstrap-with-network-fix.sh

# Update Cloudflare tunnel
./deployment/update-cf-from-host.sh
```

### Anonymous Mode Instead of Authentication
**Cause:** AUTH_MODE not properly configured
**Solution:**
```bash
# Check current auth mode
docker exec $(docker ps -q -f name=dashboard) env | grep AUTH_MODE

# In Coolify, ensure:
NEXT_PUBLIC_AUTH_MODE=multi-tenant
AUTH_MODE=multi-tenant

# Redeploy dashboard service from Coolify
```

## Notes

- Build time: ~15-30 minutes on 2 vCPU server
- Minimum specs: 4GB RAM, 2 vCPUs
- All images built for linux/amd64 platform
- Registry: docker.reactmotion.com
- Repository: my-docker-repo/dittofeed
- Dashboard base path: /dashboard (required for routing)