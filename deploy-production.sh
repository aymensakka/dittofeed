#!/bin/bash

# Deploy Dittofeed Multi-tenant with Embedded Dashboard

set -e

echo "🚀 Starting Dittofeed Multi-tenant Deployment..."

# Check if .env.production exists
if [ ! -f .env.production ]; then
    echo "❌ .env.production file not found!"
    echo "Please create .env.production with your configuration"
    exit 1
fi

# Load environment variables
export $(cat .env.production | grep -v '^#' | xargs)

# Check required environment variables
if [ -z "$GOOGLE_CLIENT_ID" ] || [ -z "$GOOGLE_CLIENT_SECRET" ]; then
    echo "❌ Missing required environment variables!"
    echo "Please set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .env.production"
    exit 1
fi

# Stop existing containers if running
echo "📦 Stopping existing containers..."
docker-compose -f docker-compose.production.yml down

# Start services
echo "🔧 Starting services..."
docker-compose -f docker-compose.production.yml up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to start..."
sleep 10

# Check service status
echo "✅ Checking service status..."
docker-compose -f docker-compose.production.yml ps

# Run database migrations
echo "🗄️ Running database migrations..."
docker-compose -f docker-compose.production.yml exec -T api npx drizzle-kit push:pg --config=drizzle.config.ts || true

echo "✨ Deployment complete!"
echo ""
echo "📍 Services are running at:"
echo "   Dashboard: http://localhost:3000"
echo "   API: http://localhost:3001"
echo ""
echo "📊 To view logs:"
echo "   docker-compose -f docker-compose.production.yml logs -f [service-name]"
echo ""
echo "🛑 To stop services:"
echo "   docker-compose -f docker-compose.production.yml down"