#!/bin/bash
# Setup environment variables for local testing

echo "=== Setting up Environment Variables ==="
echo ""

# Generate secure passwords
POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
REDIS_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
JWT_SECRET=$(openssl rand -base64 32)
SECRET_KEY=$(openssl rand -base64 32)
NEXTAUTH_SECRET=$(openssl rand -base64 32)

# Create .env file
cat > .env << EOF
# Dittofeed Environment Variables
# Generated on $(date)

# Node Environment
NODE_ENV=production

# Authentication Mode
AUTH_MODE=multi-tenant

# Database Configuration
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
DATABASE_URL=postgresql://dittofeed:${POSTGRES_PASSWORD}@postgres:5432/dittofeed

# Redis Configuration
REDIS_PASSWORD=${REDIS_PASSWORD}

# Security Keys
JWT_SECRET=${JWT_SECRET}
SECRET_KEY=${SECRET_KEY}
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}

# URLs
API_BASE_URL=https://api.com.caramelme.com
DASHBOARD_URL=https://dashboard.com.caramelme.com
NEXTAUTH_URL=https://dashboard.com.caramelme.com
CORS_ORIGIN=https://dashboard.com.caramelme.com

# Bootstrap Configuration
BOOTSTRAP_WORKSPACE_NAME=Default
BOOTSTRAP_WORKSPACE_ADMIN_EMAIL=admin@example.com

# Cloudflare Tunnel (UPDATE THIS!)
CF_TUNNEL_TOKEN=YOUR_TUNNEL_TOKEN_HERE

# Optional
CLICKHOUSE_HOST=
TEMPORAL_ADDRESS=
WORKER_ID=worker-1
EOF

echo "✅ Created .env file with generated passwords"
echo ""
echo "⚠️  IMPORTANT: Update CF_TUNNEL_TOKEN with your actual tunnel token!"
echo ""
echo "Generated passwords:"
echo "  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}"
echo "  REDIS_PASSWORD: ${REDIS_PASSWORD}"
echo ""
echo "To use these environment variables:"
echo "  1. Copy these values to Coolify's environment variables"
echo "  2. Or run locally with: docker compose --env-file .env -f docker-compose.coolify.yaml up -d"
echo ""
echo "Note: The .env file is git-ignored for security"