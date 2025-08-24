#!/bin/bash

# Restart Dittofeed deployment with fixed health checks

set -e

echo "🔄 Restarting Dittofeed deployment with fixed health checks..."

# Stop existing containers
echo "Stopping existing containers..."
docker-compose -f docker-compose.coolify-embedded.yaml down

# Wait a moment for cleanup
sleep 3

# Start services again
echo "Starting services with updated health checks..."
docker-compose -f docker-compose.coolify-embedded.yaml up -d

# Wait for services to initialize
echo "Waiting for services to initialize..."
sleep 15

# Check status
echo ""
echo "📊 Service Status:"
docker-compose -f docker-compose.coolify-embedded.yaml ps

# Show health status
echo ""
echo "🏥 Health Check Status:"
for service in api dashboard worker; do
    container="dittofeed-multitenant-${service}-1"
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container"; then
        status=$(docker ps --format "{{.Status}}" --filter "name=$container")
        echo "$service: $status"
    fi
done

echo ""
echo "✅ Deployment restarted. Monitor logs with:"
echo "   docker-compose -f docker-compose.coolify-embedded.yaml logs -f api"
echo "   docker-compose -f docker-compose.coolify-embedded.yaml logs -f dashboard"