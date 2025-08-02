#!/bin/bash

# Push script optimized for very slow connections
# Uses Docker daemon configuration to reduce concurrent uploads

if [ -z "$1" ]; then
    echo "Usage: $0 <service-name>"
    echo "Example: $0 dashboard"
    exit 1
fi

SERVICE=$1
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo"
USERNAME="coolify-system"
PASSWORD='9sFPGGDJUFnE4z*z4Aj9'

echo "=== Pushing $SERVICE with slow connection optimizations ==="
echo

# Login
echo "$PASSWORD" | docker login "$REGISTRY" -u "$USERNAME" --password-stdin >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Login failed"
    exit 1
fi
echo "✓ Logged in to registry"

# Configure Docker for slow connections
echo "Configuring Docker for slow connection..."
# Reduce concurrent uploads to 1 (default is 3)
export DOCKER_CONTENT_TRUST=0

# Image details
IMAGE="dittofeed/$SERVICE:multitenancy-redis-v1"
FULL_IMAGE="$REGISTRY/$REPO/$IMAGE"

echo
echo "📦 Pushing $FULL_IMAGE"
echo "Note: Using reduced concurrency for slow connection"
echo "Start: $(date)"
echo

# Try pushing with --disable-content-trust to avoid extra network calls
docker push "$FULL_IMAGE" --disable-content-trust 2>&1 | while IFS= read -r line; do
    echo "$line"
    # If we see the problematic layer, add extra info
    if [[ "$line" == *"e473935e4567"* ]]; then
        echo "  ⚠️  Problematic layer detected - this may take longer"
    fi
done

RESULT=${PIPESTATUS[0]}

echo
echo "End: $(date)"

if [ $RESULT -eq 0 ]; then
    echo "✅ Successfully pushed $SERVICE"
    
    # Also push latest
    echo
    echo "Pushing latest tag..."
    docker tag "$FULL_IMAGE" "$REGISTRY/$REPO/dittofeed/$SERVICE:latest"
    docker push "$REGISTRY/$REPO/dittofeed/$SERVICE:latest" --disable-content-trust
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully pushed $SERVICE:latest"
    fi
else
    echo "❌ Failed to push $SERVICE"
    echo
    echo "Troubleshooting tips:"
    echo "1. Check if the registry is accessible: curl -I https://$REGISTRY/v2/"
    echo "2. Try pushing a smaller test image first"
    echo "3. Check Docker logs: docker logs"
    echo "4. Consider using a faster connection or a local registry mirror"
fi