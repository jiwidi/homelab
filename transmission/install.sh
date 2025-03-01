#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

# Start the transmission container
docker-compose -f "$DIR/docker-compose.yaml" up -d
