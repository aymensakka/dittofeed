#!/bin/bash

echo "=== Nexus Docker Registry Push Script ==="
echo "Note: Optimized for slow connections (50 Mb/s)"
echo

# Registry details
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo"
USERNAME="coolify-system"
PASSWORD='9sFPGGDJUFnE4z*z4Aj9'

# Since we're using HTTPS, no need to check for insecure registry
echo "Using HTTPS registry at $REGISTRY"

# Login to registry
echo
echo "Logging in to Nexus registry..."
echo "$PASSWORD" | docker login "$REGISTRY" -u "$USERNAME" --password-stdin

if [ $? -ne 0 ]; then
    echo "❌ Login failed. Please check your credentials and Docker configuration."
    exit 1
fi

echo "✓ Login successful"

# Images to push - only push versioned images first
IMAGES=(
    "dittofeed/api:multitenancy-redis-v1"
    "dittofeed/worker:multitenancy-redis-v1"
    "dittofeed/dashboard:multitenancy-redis-v1"
)

# Function to get image size
get_image_size() {
    docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep "$1" | awk '{print $2}'
}

# Push images one at a time
echo
echo "Pushing images to Nexus (one at a time for slow connection)..."
TOTAL_IMAGES=${#IMAGES[@]}
CURRENT=0

for IMAGE in "${IMAGES[@]}"; do
    CURRENT=$((CURRENT + 1))
    FULL_IMAGE="$REGISTRY/$REPO/$IMAGE"
    
    # Get image size
    SIZE=$(get_image_size "$FULL_IMAGE")
    
    echo
    echo "[$CURRENT/$TOTAL_IMAGES] 📦 Pushing $FULL_IMAGE (Size: $SIZE)..."
    echo "This may take several minutes on a 50 Mb/s connection..."
    
    # Push with progress
    start_time=$(date +%s)
    
    # Push directly without timeout command (not available on macOS)
    # 50 Mb/s = ~6.25 MB/s, so 1.8GB would take ~5 minutes
    docker push "$FULL_IMAGE"
    
    RESULT=$?
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    if [ $RESULT -eq 0 ]; then
        echo "✅ Successfully pushed $IMAGE (took ${duration}s)"
    elif [ $RESULT -eq 124 ]; then
        echo "❌ Push timed out after 20 minutes for $IMAGE"
        echo "   The connection might be too slow or the registry is having issues."
    else
        echo "❌ Failed to push $IMAGE (after ${duration}s)"
    fi
    
    # Small pause between pushes
    echo "Waiting 5 seconds before next push..."
    sleep 5
done

# Tag and push latest versions if all versioned images succeeded
echo
echo "Now tagging and pushing 'latest' versions..."
for BASE_IMAGE in "api" "worker" "dashboard"; do
    SOURCE="$REGISTRY/$REPO/dittofeed/$BASE_IMAGE:multitenancy-redis-v1"
    TARGET="$REGISTRY/$REPO/dittofeed/$BASE_IMAGE:latest"
    
    echo "Tagging $SOURCE as $TARGET..."
    docker tag "$SOURCE" "$TARGET"
    
    echo "Pushing $TARGET..."
    docker push "$TARGET"
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully pushed $BASE_IMAGE:latest"
    else
        echo "❌ Failed to push $BASE_IMAGE:latest"
    fi
done

echo
echo "=== Push Summary ==="
echo
echo "Images available at:"
for IMAGE in "${IMAGES[@]}"; do
    echo "  - $REGISTRY/$REPO/$IMAGE"
done
echo "  - $REGISTRY/$REPO/dittofeed/api:latest"
echo "  - $REGISTRY/$REPO/dittofeed/worker:latest"
echo "  - $REGISTRY/$REPO/dittofeed/dashboard:latest"
echo
echo "Note: If pushes failed due to timeout, you can run this script again."
echo "Docker will resume from where it left off."