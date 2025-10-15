#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export COMPOSE_HTTP_TIMEOUT=300
cd "$HERE"
echo "Starting core stack (no camunda, no llm profile)..."
docker compose up -d
echo "You can enable Camunda with: docker compose --profile camunda up -d"
echo "You can enable local Ollama LLM with: docker compose --profile llm up -d"
echo "Waiting for services to stabilize (sleeping 20s)..."
sleep 20
echo "Services started. Useful URLs:"
echo "  Spring service: http://localhost:8080/api/health"
echo "  Postgres: localhost:5432 (user: ai / password: ai)"
echo "  Redis: localhost:6379"
echo "  Kafka bootstrap: localhost:9092"
echo "  ArangoDB web: http://localhost:8529  (user: root / password from .env)"
echo "  Chroma vector DB: http://localhost:8000"
echo "  Meilisearch: http://localhost:7700"
echo "  Langfuse: http://localhost:3000 (may take time to initialize)"
echo ""
echo "To view logs: docker compose logs -f server"
