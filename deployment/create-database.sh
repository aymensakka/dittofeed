#!/bin/bash
# Create the dittofeed database in PostgreSQL

echo "==========================================="
echo "🗄️ Creating PostgreSQL Database"
echo "==========================================="

# Find the postgres container
POSTGRES_CONTAINER=$(docker ps | grep postgres | awk '{print $1}')

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "❌ PostgreSQL container not found"
    exit 1
fi

echo "Found PostgreSQL container: $POSTGRES_CONTAINER"

# Create the database
echo "Creating 'dittofeed' database..."
docker exec -it $POSTGRES_CONTAINER psql -U dittofeed -d postgres -c "CREATE DATABASE dittofeed;" 2>/dev/null || echo "Database may already exist"

# Verify database exists
echo ""
echo "Verifying database..."
docker exec -it $POSTGRES_CONTAINER psql -U dittofeed -d postgres -c "\l" | grep dittofeed

echo ""
echo "✅ Database setup complete"
echo ""
echo "Now restart the services in Coolify to reconnect with the database."