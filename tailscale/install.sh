#!/bin/bash
set -e

# Create data directory if it doesn't exist
DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/data"

if [ -z "$TAILSCALE_AUTH_KEY" ]; then
  echo "WARNING: TAILSCALE_AUTH_KEY not set in .env file"
  echo "Please generate an auth key at https://login.tailscale.com/admin/settings/keys"
  echo "and add it to your .env file as TAILSCALE_AUTH_KEY=your-auth-key"
  exit 1
fi

# Run the Tailscale container
docker compose --file "$DIR/docker-compose.yaml" up -d

echo "Tailscale container started. You can verify your Tailscale connection at:"
echo "https://login.tailscale.com/admin/machines"