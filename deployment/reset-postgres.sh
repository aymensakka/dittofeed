#!/bin/bash
# Reset PostgreSQL to trigger init scripts

echo "=== Resetting PostgreSQL Database ==="

# Stop all containers using postgres
echo "Stopping containers..."
docker stop $(docker ps -q -f name=postgres) 2>/dev/null || true
docker stop $(docker ps -q -f name=api) 2>/dev/null || true
docker stop $(docker ps -q -f name=worker) 2>/dev/null || true
docker stop $(docker ps -q -f name=dashboard) 2>/dev/null || true

# Remove postgres container
echo "Removing postgres container..."
docker rm $(docker ps -aq -f name=postgres) 2>/dev/null || true

# Now remove the volume
echo "Removing postgres volume..."
docker volume rm $(docker volume ls -q | grep postgres_data) 2>/dev/null || true

echo ""
echo "✅ PostgreSQL reset complete"
echo "Now redeploy in Coolify - the init script will run on fresh database"