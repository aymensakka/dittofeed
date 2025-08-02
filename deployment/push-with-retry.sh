#!/bin/bash

# Push script with automatic retries for slow connections
# Usage: ./push-with-retry.sh <service-name>

if [ -z "$1" ]; then
    echo "Usage: $0 <service-name>"
    echo "Example: $0 worker"
    exit 1
fi

SERVICE=$1
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo"
USERNAME="coolify-system"
PASSWORD='9sFPGGDJUFnE4z*z4Aj9'
MAX_RETRIES=5
RETRY_DELAY=30

echo "=== Pushing $SERVICE with automatic retries ==="
echo "Max retries: $MAX_RETRIES"
echo "Retry delay: $RETRY_DELAY seconds"
echo

# Login
echo "$PASSWORD" | docker login "$REGISTRY" -u "$USERNAME" --password-stdin >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Login failed"
    exit 1
fi
echo "✓ Logged in to registry"

# Image details
IMAGE="dittofeed/$SERVICE:multitenancy-redis-v1"
FULL_IMAGE="$REGISTRY/$REPO/$IMAGE"

# Function to push with retries
push_with_retries() {
    local tag=$1
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        echo
        echo "Attempt $attempt/$MAX_RETRIES for $tag..."
        echo "Start: $(date)"
        
        # Push and capture exit code
        docker push "$REGISTRY/$REPO/dittofeed/$SERVICE:$tag" 2>&1 | tee /tmp/push_output.txt
        RESULT=${PIPESTATUS[0]}
        
        if [ $RESULT -eq 0 ]; then
            echo "✅ Successfully pushed $SERVICE:$tag"
            return 0
        else
            # Check if it's a layer already exists error (which is actually success)
            if grep -q "Layer already exists" /tmp/push_output.txt && ! grep -q "failed" /tmp/push_output.txt; then
                echo "✅ Image already exists in registry"
                return 0
            fi
            
            echo "❌ Push failed (attempt $attempt/$MAX_RETRIES)"
            
            if [ $attempt -lt $MAX_RETRIES ]; then
                echo "Waiting $RETRY_DELAY seconds before retry..."
                sleep $RETRY_DELAY
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Push versioned tag
echo
echo "📦 Pushing $FULL_IMAGE"
push_with_retries "multitenancy-redis-v1"

if [ $? -eq 0 ]; then
    # Also push latest tag
    echo
    echo "📦 Now pushing latest tag..."
    docker tag "$FULL_IMAGE" "$REGISTRY/$REPO/dittofeed/$SERVICE:latest"
    push_with_retries "latest"
else
    echo
    echo "❌ Failed to push $SERVICE after $MAX_RETRIES attempts"
    echo "You may need to check your network connection or registry status"
fi

# Cleanup
rm -f /tmp/push_output.txt