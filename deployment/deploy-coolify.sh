#!/bin/bash

# ==============================================================================
# Deploy to Coolify Server
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}Deploying to Coolify${NC}"
echo -e "${BLUE}===================================================${NC}"

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
    echo -e "${GREEN}✓ Loaded environment variables${NC}"
else
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi

# Validate required variables
if [ -z "$SERVER_IP" ] || [ -z "$SSH_USER" ] || [ -z "$SSH_KEY_PATH" ]; then
    echo -e "${RED}✗ Missing server configuration in .env${NC}"
    echo "Please set: SERVER_IP, SSH_USER, SSH_KEY_PATH"
    exit 1
fi

# Expand the tilde in SSH_KEY_PATH
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

# Check if SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}✗ SSH key not found at: $SSH_KEY_PATH${NC}"
    exit 1
fi

echo -e "\n${BLUE}Configuration:${NC}"
echo "Server: $SERVER_IP"
echo "User: $SSH_USER"
echo "SSH Key: $SSH_KEY_PATH"
echo "Coolify Path: $COOLIFY_SERVICE_PATH"

# Function to run SSH commands
run_ssh() {
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "$1"
}

# Step 1: Push latest changes to git
echo -e "\n${YELLOW}Pushing latest changes to git...${NC}"
git add -A
git commit -m "deployment: update configuration" || true
git push origin main

# Step 2: Pull latest changes on server
echo -e "\n${YELLOW}Pulling latest changes on server...${NC}"
run_ssh "cd $COOLIFY_SERVICE_PATH && git pull"

# Step 3: Initialize databases (if needed)
echo -e "\n${YELLOW}Checking database initialization...${NC}"
run_ssh "cd $COOLIFY_SERVICE_PATH && ./deployment/init-coolify-manual.sh"

# Step 4: Trigger Coolify redeploy
echo -e "\n${YELLOW}Triggering Coolify redeploy...${NC}"
echo -e "${YELLOW}Note: You need to trigger the redeploy from Coolify UI${NC}"
echo ""
echo "Steps to complete deployment:"
echo "1. Go to your Coolify dashboard at your-coolify-url"
echo "2. Navigate to your Dittofeed application"
echo "3. Click 'Redeploy' button"
echo ""
echo "Alternatively, if you have Coolify CLI configured:"
echo "  coolify deploy --id=$COOLIFY_PROJECT_ID"

# Step 5: Monitor deployment
echo -e "\n${BLUE}To monitor deployment status:${NC}"
echo "SSH to server and run:"
echo "  docker ps | grep $COOLIFY_PROJECT_ID"
echo "  docker logs \$(docker ps -q -f name=temporal | head -1) --tail 50"

echo -e "\n${GREEN}===================================================${NC}"
echo -e "${GREEN}Deployment script completed!${NC}"
echo -e "${GREEN}===================================================${NC}"