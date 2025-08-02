# Deployment Scripts

This folder contains scripts for building and deploying Dittofeed.

## Quick Start

```bash
# Clone repository
git clone https://github.com/aymensakka/dittofeed.git
cd dittofeed

# Setup build environment (run once)
sudo ./deployment/setup-build-environment.sh

# Build and push images
./deployment/build-and-push-images.sh
```

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

Builds Dittofeed Docker images on Ubuntu VPS and pushes them to Nexus registry.

**Features:**
- Automatically pulls latest code from git
- Builds for linux/amd64 platform
- Sequential builds to avoid resource exhaustion
- Cleans Docker cache between builds
- Verifies successful push to registry

**Prerequisites:**
- Ubuntu Linux VPS (tested on Ubuntu 20.04/22.04)
- Minimum 4GB RAM, 2 vCPUs
- Dependencies installed via setup script

**Usage:**

1. **First time setup:**
   ```bash
   # Clone repository
   git clone https://github.com/aymensakka/dittofeed.git
   cd dittofeed
   
   # Install dependencies
   sudo ./deployment/setup-build-environment.sh
   
   # Build and push images
   ./deployment/build-and-push-images.sh
   ```

2. **Subsequent builds:**
   ```bash
   cd dittofeed
   ./deployment/build-and-push-images.sh
   # Script automatically pulls latest changes
   ```

3. **Building specific version:**
   ```bash
   cd dittofeed
   git checkout <tag-or-branch>
   # Comment out lines 84-87 in build script to skip auto-pull
   ./deployment/build-and-push-images.sh
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

## Troubleshooting

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