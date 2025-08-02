# Build and Deploy Workflow

This document describes the two-stage build and deploy process for Dittofeed.

## Overview

1. **Dev Server (Ubuntu)**: Builds images and pushes to Nexus
2. **Production Server (Coolify)**: Pulls images from Nexus and deploys

## Files

- `docker-compose.build.yaml` - For building images on dev server
- `docker-compose.deploy.yaml` - For deploying on production via Coolify
- `deployment/build-and-push-dev.sh` - Automation script for dev server

## Stage 1: Build on Dev Server

SSH into your Ubuntu dev server and run:

```bash
cd ~/dittofeed

# Option 1: Use the build script (recommended)
./deployment/build-and-push-dev.sh

# Option 2: Use docker-compose directly
docker login docker.reactmotion.com -u coolify-system -p '9sFPGGDJUFnE4z*z4Aj9'
docker-compose -f docker-compose.build.yaml build
docker-compose -f docker-compose.build.yaml push
```

This will:
- Build all three images (api, dashboard, worker)
- Tag them as `multitenancy-redis-v1`
- Push them to your Nexus registry

## Stage 2: Deploy via Coolify

### Setup in Coolify

1. **Use the deploy compose file**: Point Coolify to `docker-compose.deploy.yaml`

2. **Set environment variables** in Coolify:
   ```
   POSTGRES_PASSWORD=<your-password>
   REDIS_PASSWORD=<your-password>
   JWT_SECRET=<your-secret>
   ENCRYPTION_KEY=<your-key>
   NEXTAUTH_SECRET=<your-secret>
   DOMAIN=<your-domain>
   API_BASE_URL=https://api.<your-domain>
   CORS_ORIGIN=https://dashboard.<your-domain>
   NEXT_PUBLIC_API_URL=https://api.<your-domain>
   NEXTAUTH_URL=https://dashboard.<your-domain>
   
   # Docker Registry Credentials
   DOCKER_REGISTRY_USERNAME=coolify-system
   DOCKER_REGISTRY_PASSWORD=9sFPGGDJUFnE4z*z4Aj9
   ```

3. **Set pre-deployment command**:
   ```bash
   docker login docker.reactmotion.com -u coolify-system -p '9sFPGGDJUFnE4z*z4Aj9'
   ```

4. **Deploy**: Coolify will pull the images from Nexus and run them

## Advantages

- **Separation of concerns**: Build server handles compilation, production only runs
- **Consistent builds**: All deployments use the same pre-built images
- **Faster deployments**: No building on production server
- **Rollback capability**: Previous images remain in Nexus
- **Security**: Production server doesn't need source code

## Updating Images

When you need to deploy new code:

1. Make changes and push to GitHub
2. On dev server: `./deployment/build-and-push-dev.sh`
3. In Coolify: Trigger redeployment
4. Coolify pulls new images (due to `pull_policy: always`)

## Notes

- Images are always tagged `multitenancy-redis-v1` (consider versioning in future)
- The deploy compose has `pull_policy: always` to ensure latest images
- Dev server needs ~4GB RAM for building
- Production server only needs resources to run containers