# Deployment Scripts

This folder contains scripts for building and deploying Dittofeed.

## build-and-push-images.sh

This script builds Dittofeed Docker images on an Ubuntu VPS and pushes them to your Nexus registry.

### Prerequisites

- Ubuntu Linux VPS (tested on Ubuntu 20.04/22.04)
- Docker installed and running
- Git installed
- Node.js and Yarn installed
- Access to the Nexus registry

### Usage

1. SSH into your Ubuntu VPS
2. Clone the Dittofeed repository:
   ```bash
   git clone https://github.com/aymensakka/dittofeed.git
   cd dittofeed
   ```

3. Run the build script:
   ```bash
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

### Notes

- Build time: ~10-20 minutes depending on VPS specs
- Recommended VPS specs: 4GB RAM, 2 vCPUs minimum
- The script uses the production configuration
- All images are built for linux/amd64 platform only