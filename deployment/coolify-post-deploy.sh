#!/bin/bash
# Post-deployment script for Coolify to ensure database exists

echo "=== Post-Deployment Database Setup ==="

# Wait for postgres to be ready
echo "Waiting for PostgreSQL..."
sleep 5

# Try to create database (will fail gracefully if exists)
docker exec $(docker ps -q -f name=postgres) psql -U postgres -c "CREATE DATABASE dittofeed;" 2>/dev/null || true
docker exec $(docker ps -q -f name=postgres) psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE dittofeed TO dittofeed;" 2>/dev/null || true

echo "Database setup attempted"

# Restart API and Worker to reconnect
docker restart $(docker ps -q -f name=api) 2>/dev/null || true
docker restart $(docker ps -q -f name=worker) 2>/dev/null || true

echo "Services restarted"