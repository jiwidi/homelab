#!/bin/bash
set -e

MODULE_DIR="$(dirname "$0")"
docker-compose -f "$MODULE_DIR/docker-compose.yaml" up -d
