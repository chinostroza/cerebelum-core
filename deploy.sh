#!/bin/bash

# ====================================
# Cerebelum Core - Deployment Script
# ====================================
#
# This script deploys Cerebelum Core to a production server
# Usage: ./deploy.sh

set -e  # Exit on error

echo "🚀 Starting Cerebelum Core deployment..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please create .env from .env.example and configure it."
    echo "  cp .env.example .env"
    echo "  # Then edit .env with your production values"
    exit 1
fi

# Load environment variables
echo "📝 Loading environment variables..."
export $(grep -v '^#' .env | xargs)

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed!"
    echo "Please install Docker first: https://docs.docker.com/engine/install/"
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker compose &> /dev/null; then
    echo "❌ Error: Docker Compose is not installed!"
    echo "Please install Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi

# Pull latest changes (if using git)
if [ -d .git ]; then
    echo "📦 Pulling latest changes from git..."
    git pull origin main || git pull origin master
fi

# Stop existing containers
echo "🛑 Stopping existing containers..."
docker compose down

# Build the Docker image
echo "🔨 Building Docker image..."
docker compose build app

# Start the services
echo "🚀 Starting services..."
docker compose up -d

# Wait for database to be ready
echo "⏳ Waiting for database to be ready..."
sleep 5

# Run migrations
echo "🔄 Running database migrations..."
docker compose exec -T app bin/cerebelum_core eval "Cerebelum.Release.migrate()"

# Show container status
echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Container status:"
docker compose ps

echo ""
echo "📝 View logs with:"
echo "  docker compose logs -f app"
echo ""
echo "🔍 Check application status:"
echo "  docker compose exec app bin/cerebelum_core rpc \"IO.puts('Cerebelum is running!')\""
echo ""
echo "🌐 gRPC server should be running on port: ${GRPC_PORT:-9090}"
