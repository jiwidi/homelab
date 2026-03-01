#!/bin/bash
set -e

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
VERT_DIR="$SCRIPT_DIR/vert-source"

if [ ! -d "$VERT_DIR" ]; then
  echo "Cloning VERT repository into $VERT_DIR..."
  git clone https://github.com/VERT-sh/VERT.git "$VERT_DIR"
else
  echo "VERT source already present, skipping clone."
fi

echo "Starting Vert service from $SCRIPT_DIR..."
docker-compose -f "$SCRIPT_DIR/docker-compose.yaml" up -d
echo "Vert service started."