#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

# docker compose reads ./.env by itself, but the guards below and the mkdir need
# the values in the shell too. Sourcing keeps this script working standalone as
# well as under master_install.sh (which exports the repo-root .env instead).
if [ -f "$DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$DIR/.env"
  set +a
fi

: "${WIREGUARD_PRIVATE_KEY:?Need WIREGUARD_PRIVATE_KEY in .env (Mullvad WireGuard config, [Interface] PrivateKey)}"
: "${WIREGUARD_ADDRESSES:?Need WIREGUARD_ADDRESSES in .env (Mullvad WireGuard config, [Interface] Address -- IPv4 only)}"
: "${MEDIA_ROOT:?Need MEDIA_ROOT in .env}"

# Sonarr/Radarr hardlink from /data/torrents into /data/media. That only works
# if both live under the single mount created below -- see docker-compose.yaml.
mkdir -p "$MEDIA_ROOT"/torrents/{tv,movies} "$MEDIA_ROOT"/media/{tv,movies}

docker compose --file "$DIR/docker-compose.yaml" up -d
