# Dashboard Image Transfer Guide

This guide explains how to transfer and deploy the dashboard image that couldn't be pushed due to network limitations.

## Current Status

- ✅ API image: Successfully pushed to registry
- ✅ Worker image: Successfully pushed to registry  
- ❌ Dashboard image: Saved locally as `dashboard.tar.gz` (386MB)

## Step 1: Transfer the Dashboard Image

The dashboard image has been saved to: `exports/dashboard.tar.gz` (386MB)

Transfer this file to a server with better internet connectivity using one of these methods:

### Option A: Using SCP
```bash
scp exports/dashboard.tar.gz user@your-server:/tmp/
```

### Option B: Using rsync (with resume capability)
```bash
rsync -avP exports/dashboard.tar.gz user@your-server:/tmp/
```

### Option C: Using cloud storage
```bash
# Upload to cloud storage (e.g., S3, Google Drive, Dropbox)
# Then download from the server
```

## Step 2: Load and Push from Remote Server

1. **SSH into the server** with better connectivity:
```bash
ssh user@your-server
```

2. **Navigate to the transfer directory**:
```bash
cd /tmp
```

3. **Copy the push script**:
```bash
# Copy the contents of exports/load-and-push-dashboard.sh to the server
# Or create it manually with the registry credentials
```

4. **Run the load and push script**:
```bash
chmod +x load-and-push-dashboard.sh
./load-and-push-dashboard.sh
```

This will:
- Load the dashboard image from `dashboard.tar.gz`
- Login to the Nexus registry
- Push both `multitenancy-redis-v1` and `latest` tags

## Step 3: Deploy Without Dashboard (Immediate Option)

While waiting for the dashboard transfer, you can deploy the API and Worker services:

1. **Use the no-dashboard compose file**:
```bash
docker-compose -f docker-compose.no-dashboard.yaml up -d
```

2. **Verify services are running**:
```bash
docker-compose -f docker-compose.no-dashboard.yaml ps
docker-compose -f docker-compose.no-dashboard.yaml logs
```

3. **Access the API**:
- API Health: https://api.com.caramelme.com/health
- The API and Worker will function normally without the dashboard

## Step 4: Add Dashboard After Push

Once the dashboard image is successfully pushed to the registry:

1. **Update Cloudflare tunnel** (if needed) to route dashboard traffic
2. **Use the full docker-compose.yaml**:
```bash
docker-compose down
docker-compose up -d
```

## Alternative: Local Registry

If transferring to another server isn't feasible, consider setting up a local registry:

```bash
# Start a local registry
docker run -d -p 5000:5000 --name registry registry:2

# Tag for local registry
docker tag docker.reactmotion.com/my-docker-repo/dittofeed/dashboard:multitenancy-redis-v1 localhost:5000/dashboard:latest

# Push to local registry (no internet needed)
docker push localhost:5000/dashboard:latest
```

## Verification Commands

After successful push, verify the images in the registry:

```bash
# Check all images
curl -u coolify-system:'9sFPGGDJUFnE4z*z4Aj9' https://docker.reactmotion.com/v2/_catalog

# Check dashboard tags
curl -u coolify-system:'9sFPGGDJUFnE4z*z4Aj9' https://docker.reactmotion.com/v2/my-docker-repo/dittofeed/dashboard/tags/list
```

## Summary

1. **Immediate deployment**: Use `docker-compose.no-dashboard.yaml` to deploy API and Worker
2. **Dashboard transfer**: Transfer `exports/dashboard.tar.gz` (386MB) to a server with better connectivity
3. **Push from remote**: Use the provided script to load and push the dashboard image
4. **Full deployment**: Switch to the complete `docker-compose.yaml` once dashboard is in registry