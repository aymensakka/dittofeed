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
```bash
# After Coolify deploys the stack
cd ~/dittofeed

# Check status and bootstrap
./deployment/bootstrap-simple.sh
./deployment/manual-bootstrap.sh  # If workspace doesn't exist

# Setup Cloudflare tunnel updates
sudo crontab -e
# Add: */5 * * * * /root/dittofeed/deployment/update-cf-from-host.sh

# Access the application
# https://communication-dashboard.caramelme.com
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
| `bootstrap-simple.sh` | Quick status check | Check deployment status |
| `manual-bootstrap.sh` | Interactive workspace creation | Create workspace manually |
| `bootstrap-with-network-fix.sh` | Complete network setup | Fix network issues, IP changes |
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

1. **Initial Bootstrap (after deployment):**
   ```bash
   # Check deployment status
   ./deployment/bootstrap-simple.sh
   
   # If workspace doesn't exist, create it
   ./deployment/manual-bootstrap.sh
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

Key environment variables for multi-tenant mode:
- `AUTH_MODE=multi-tenant`
- `NEXT_PUBLIC_AUTH_MODE=multi-tenant`
- `WORKSPACE_ISOLATION_ENABLED=true`
- `BOOTSTRAP_WORKSPACE_NAME=caramel`
- `DOMAIN=caramelme.com`

### Common Multi-Tenant Issues

1. **404 on Dashboard (All Routes):**
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

2. **Bad Gateway After Redeploy:**
   - Container IPs changed
   - Run `update-cf-from-host.sh`
   - Check tunnel status with `debug-cloudflared.sh`

3. **Workspace Not Found:**
   ```sql
   -- Check workspace in database
   docker exec $(docker ps -q -f name=postgres) psql -U dittofeed -d dittofeed -c "SELECT name, domain FROM \"Workspace\";"
   ```

4. **Dashboard Returns 404 for All Routes:**
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

## Notes

- Build time: ~15-30 minutes on 2 vCPU server
- Minimum specs: 4GB RAM, 2 vCPUs
- All images built for linux/amd64 platform
- Registry: docker.reactmotion.com
- Repository: my-docker-repo/dittofeed