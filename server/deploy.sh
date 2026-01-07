#!/bin/bash
# VibedTracker Server Deploy Script
# Usage: ./deploy.sh [dev|prod]

set -e

MODE=${1:-prod}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 VibedTracker Deploy ($MODE)"
echo "================================"

# Check .env
if [ ! -f .env ]; then
    echo "❌ .env nicht gefunden!"
    echo "   Kopiere .env.example zu .env und konfiguriere die Werte."
    exit 1
fi

# Pull latest changes
echo "📥 Git pull..."
git pull origin main

# Build and start
if [ "$MODE" = "dev" ]; then
    echo "🔧 Development Mode (Port 8080)"
    docker-compose down
    docker-compose up -d --build
else
    echo "🌐 Production Mode (Traefik)"
    docker-compose -f docker-compose.yml -f docker-compose.prod.yml down
    docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
fi

# Wait for health check
echo "⏳ Warte auf API..."
sleep 5

# Check health
if curl -s http://localhost:8080/health > /dev/null 2>&1 || curl -s http://127.0.0.1:8080/health > /dev/null 2>&1; then
    echo "✅ API läuft!"
else
    echo "⚠️  Health check fehlgeschlagen - prüfe Logs:"
    echo "   docker-compose logs api"
fi

echo ""
echo "📊 Container Status:"
docker-compose ps

echo ""
echo "🔗 Nützliche Befehle:"
echo "   Logs:     docker-compose logs -f api"
echo "   Restart:  docker-compose restart api"
echo "   Stop:     docker-compose down"
