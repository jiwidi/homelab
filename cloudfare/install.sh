#!/bin/bash
set -e

MODULE_DIR="$(dirname "$0")"
docker compose --file "$MODULE_DIR/docker-compose.yaml" up -d
