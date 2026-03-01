#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
: "${TWINGATE_NETWORK:?Need TWINGATE_NETWORK in .env}"
: "${TWINGATE_ACCESS_TOKEN:?Need TWINGATE_ACCESS_TOKEN in .env}"
: "${TWINGATE_REFRESH_TOKEN:?Need TWINGATE_REFRESH_TOKEN in .env}"
docker compose --file "$DIR/docker-compose.yaml" up -d
