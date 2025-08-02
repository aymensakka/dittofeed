#!/bin/bash
# Check status of all Dittofeed images (local and registry)

# Configuration
REGISTRY="docker.reactmotion.com"
REPO="my-docker-repo/dittofeed"
TAG="multitenancy-redis-v1"

# Registry credentials
REGISTRY_USER="coolify-system"
REGISTRY_PASS='9sFPGGDJUFnE4z*z4Aj9'

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Dittofeed Images Status ===${NC}"
echo

# Check local images
echo -e "${YELLOW}LOCAL IMAGES:${NC}"
for service in api dashboard worker; do
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "$REGISTRY/$REPO/$service:$TAG"; then
        SIZE=$(docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep "$service:$TAG" | awk '{print $2}')
        echo -e "  ${GREEN}✓${NC} $service: $SIZE"
    else
        echo -e "  ${RED}✗${NC} $service: not found locally"
    fi
done

echo
echo -e "${YELLOW}REGISTRY STATUS:${NC}"
for service in api dashboard worker; do
    if curl -sf -u "$REGISTRY_USER:$REGISTRY_PASS" \
        "https://$REGISTRY/v2/$REPO/$service/tags/list" 2>/dev/null | grep -q "$TAG"; then
        echo -e "  ${GREEN}✓${NC} $service: in registry"
    else
        echo -e "  ${RED}✗${NC} $service: NOT in registry"
    fi
done

echo
echo -e "${YELLOW}MISSING IMAGES:${NC}"
MISSING=0
for service in api dashboard worker; do
    LOCAL_EXISTS=false
    REGISTRY_EXISTS=false
    
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "$REGISTRY/$REPO/$service:$TAG"; then
        LOCAL_EXISTS=true
    fi
    
    if curl -sf -u "$REGISTRY_USER:$REGISTRY_PASS" \
        "https://$REGISTRY/v2/$REPO/$service/tags/list" 2>/dev/null | grep -q "$TAG"; then
        REGISTRY_EXISTS=true
    fi
    
    if [ "$LOCAL_EXISTS" = false ] || [ "$REGISTRY_EXISTS" = false ]; then
        echo "  $service:"
        [ "$LOCAL_EXISTS" = false ] && echo "    - Build with: ./deployment/build-$service.sh"
        [ "$REGISTRY_EXISTS" = false ] && [ "$LOCAL_EXISTS" = true ] && echo "    - Push with: docker push $REGISTRY/$REPO/$service:$TAG"
        MISSING=$((MISSING + 1))
    fi
done

if [ $MISSING -eq 0 ]; then
    echo -e "  ${GREEN}All images are built and pushed!${NC}"
fi

echo
echo -e "${BLUE}================================${NC}"