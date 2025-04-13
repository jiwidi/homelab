#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

# Create data directory if it doesn't exist
if [ ! -d "$DIR/data" ]; then
  echo "Creating data directory for Dockge..."
  mkdir -p "$DIR/data"
fi

docker compose --file "$DIR/docker-compose.yaml" up -d
