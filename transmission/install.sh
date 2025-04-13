#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
docker compose --file "$DIR/docker-compose.yaml" up -d
