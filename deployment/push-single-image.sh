#!/bin/bash
# Push a single Docker image with retry logic
# Usage: ./push-single-image.sh <image:tag>

if [ $# -eq 0 ]; then
    echo "Usage: $0 <image:tag>"
    echo "Example: $0 docker.reactmotion.com/my-docker-repo/dittofeed/api:multitenancy-redis-v1"
    exit 1
fi

IMAGE=$1
ATTEMPT=0

echo "Pushing $IMAGE with infinite retry..."
echo "Press Ctrl+C to stop"

while true; do
    ATTEMPT=$((ATTEMPT + 1))
    echo ""
    echo "Attempt #$ATTEMPT - $(date)"
    
    if docker push "$IMAGE"; then
        echo "SUCCESS! Image pushed successfully."
        exit 0
    fi
    
    echo "Push failed. Retrying in 2 seconds..."
    echo "Docker will resume from where it left off"
    sleep 2
done