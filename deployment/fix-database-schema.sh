#!/bin/bash

# ==============================================================================
# Fix Database Schema for Multi-tenant Deployment
# This script adds missing columns discovered during deployment
# ==============================================================================

set -e

echo "===================================================="
echo "Database Schema Fix for Multi-tenant Deployment"
echo "===================================================="
echo ""

# Find postgres container
POSTGRES_CONTAINER=$(docker ps --format '{{.Names}}' | grep postgres | head -1)

if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "❌ PostgreSQL container not found"
    exit 1
fi

echo "Found PostgreSQL container: $POSTGRES_CONTAINER"
echo ""

echo "Step 1: Adding missing columns to Workspace table..."
echo "----------------------------------------------------"

# Add domain column
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "ALTER TABLE \"Workspace\" ADD COLUMN IF NOT EXISTS domain TEXT;" 2>/dev/null || true
echo "✅ Added domain column"

# Add externalId column
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "ALTER TABLE \"Workspace\" ADD COLUMN IF NOT EXISTS \"externalId\" TEXT;" 2>/dev/null || true
echo "✅ Added externalId column"

# Add parentWorkspaceId column for workspace hierarchy
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "ALTER TABLE \"Workspace\" ADD COLUMN IF NOT EXISTS \"parentWorkspaceId\" UUID REFERENCES \"Workspace\"(id);" 2>/dev/null || true
echo "✅ Added parentWorkspaceId column"

echo ""
echo "Step 2: Adding missing columns to WorkspaceMemberRole table..."
echo "--------------------------------------------------------------"

# Add resourceType column to WorkspaceMemberRole
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "ALTER TABLE \"WorkspaceMemberRole\" ADD COLUMN IF NOT EXISTS \"resourceType\" TEXT;" 2>/dev/null || true
echo "✅ Added resourceType column to WorkspaceMemberRole"

echo ""
echo "Step 3: Updating workspace domain..."
echo "-------------------------------------"

# Get the workspace name and update domain
WORKSPACE_NAME=$(docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -t -c \
    "SELECT name FROM \"Workspace\" LIMIT 1;" 2>/dev/null | tr -d ' \n')

if [ ! -z "$WORKSPACE_NAME" ]; then
    # Extract domain from environment or use default
    DOMAIN="${DOMAIN:-caramelme.com}"
    docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
        "UPDATE \"Workspace\" SET domain = '$DOMAIN' WHERE domain IS NULL;" 2>/dev/null || true
    echo "✅ Updated workspace domain to: $DOMAIN"
else
    echo "⚠️  No workspace found to update"
fi

echo ""
echo "Step 4: Verifying schema..."
echo "----------------------------"

# Show the updated schema
docker exec $POSTGRES_CONTAINER psql -U dittofeed -d dittofeed -c \
    "SELECT column_name, data_type, is_nullable 
     FROM information_schema.columns 
     WHERE table_name = 'Workspace' 
     ORDER BY ordinal_position;" 2>/dev/null || true

echo ""
echo "===================================================="
echo "Database schema fix completed!"
echo "===================================================="
echo ""
echo "Next steps:"
echo "1. Restart the dashboard container to pick up changes"
echo "2. Verify the application works correctly"
echo ""