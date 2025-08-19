#!/bin/bash

echo "Checking cloudflared container details..."

CLOUDFLARED=$(docker ps --format '{{.Names}}' | grep -i cloudflared | head -1)

echo "Container: $CLOUDFLARED"
echo ""

# Check the image
echo "Image used:"
docker inspect $CLOUDFLARED --format '{{.Config.Image}}'
echo ""

# Check the entrypoint and command
echo "Entrypoint:"
docker inspect $CLOUDFLARED --format '{{.Config.Entrypoint}}'
echo ""

echo "Command:"
docker inspect $CLOUDFLARED --format '{{.Config.Cmd}}'
echo ""

# Check volumes
echo "Volumes/Mounts:"
docker inspect $CLOUDFLARED --format '{{range .Mounts}}{{.Type}}: {{.Source}} -> {{.Destination}}{{println}}{{end}}'
echo ""

# Check if config is mounted
echo "Checking for config mount:"
docker inspect $CLOUDFLARED | grep -A2 -B2 "config.yml"
echo ""

# Check environment variables
echo "Environment variables:"
docker inspect $CLOUDFLARED --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -E "TUNNEL|CF_|TOKEN"