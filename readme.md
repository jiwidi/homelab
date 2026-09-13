# My Personal Homelab

Docker configurations and install scripts for my personal homelab on a Mac Mini M4.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Hardware

- **Mac Mini M4** — Apple M4, 32GB RAM, [2TB custom Chinese NVMe](https://item.taobao.com/item.htm?abbucket=14&id=874377707144&ns=1&priceTId=2100c80417368883046408893e0be2&skuId=5882661866398&spm=a21n57.1.hoverItem.2&utparam=%7B%22aplus_abtest%22%3A%22741a06251058619e3d5eda8db6a4078b%22%7D&xxc=taobaoSearch) replacing the internal 256GB SSD

## Services

### Always-on (Docker)

| Service | Description | Port |
|---------|-------------|------|
| **Dockge** | Compose stack management UI | 5001 |
| **Homepage** | Dashboard | 3000 |
| **Speedtest Tracker** | Internet speed monitoring | 8081 |
| **Glances** | System monitoring | 61208 |
| **Twingate** | Private remote access connector | — |
| **Cloudflare Tunnel** | Public ingress for selected services | — |
| **Playit** | Tunnel for game server ports | — |
| **Open WebUI** | Chat UI for the local llama-server | 8083 |
| **Vert** | File converter | 3002 |
| **Tailscale** | Subnet router + exit node (`luna`) | — |

### Media automation (`arr/`)

Prowlarr → Sonarr/Radarr → qBittorrent → Jellyfin. Torrent traffic leaves via
Mullvad WireGuard with a kill switch. See [`arr/README.md`](arr/README.md) for
the network topology and first-run wiring.

| Service | Port | Notes |
|---------|------|-------|
| **Jellyfin** | 8096 | **Bare-metal**, not in Docker — see below |
| **Jellyseerr** | 5055 | Request UI — the front door for everyone else |
| **Sonarr** | 8989 | TV |
| **Radarr** | 7878 | Movies |
| **Bazarr** | 6767 | Subtitles |
| **qBittorrent** | 8082 | Inside gluetun's netns; port published by gluetun |
| **Prowlarr** | 9696 | Indexers, also behind the VPN |

### Bare-metal (no Docker)

| Service | Description | Port |
|---------|-------------|------|
| **unsloth** | Local LLM inference server (Apple Metal) | 8001 |
| **Jellyfin** | Media server (VideoToolbox transcoding) | 8096 |

**Why not Docker?** Docker Desktop / Colima on macOS can't pass the Apple GPU
through to containers. For `llama.cpp` that means no Metal acceleration; for
Jellyfin it means no VideoToolbox, so it would transcode on CPU only. Both run
directly on the host and are reached from containers via
`host.docker.internal`.

> ⚠️ The Jellyfin Homebrew cask installs `Jellyfin.app` — a menu-bar app, **not**
> a daemon. It only runs while someone is logged into the desktop. Add it to
> Login Items and enable auto-login if you want it to survive unattended
> reboots.

Runs **Qwen3.6-35B-A3B** (MoE, ~3B active) on Unsloth's prebuilt Metal
llama.cpp. This machine is memory-bandwidth-bound (~120 GB/s), so generation
speed scales with *active* parameters, not total — a dense 27B measures ~5 tok/s
here and is unusable for agents. See [`unsloth/README.md`](unsloth/README.md).

```bash
./unsloth/qwen-server.sh              # thinking on (default)
./unsloth/qwen-server.sh off          # non-thinking, faster
./unsloth/qwen-server.sh budget=512   # thinking hard-capped at 512 tokens
```

Point Claude Code at it:
```bash
ANTHROPIC_BASE_URL=http://localhost:8001 ANTHROPIC_API_KEY=$LLM_API_KEY \
  claude --model unsloth/Qwen3.6-35B-A3B
```

## Remote Access

### Private (web UIs, SSH) — Twingate
Web UIs, management ports, and SSH are reached via **Twingate**. No ports are exposed to the internet. Install the Twingate client, authenticate, and reach services at their `localhost` address. Define a Resource per service in the Twingate admin console (e.g. `localhost:3000` for Homepage, `localhost:5001` for Dockge).

### Tailnet (media, SSH) — Tailscale
The `tailscale/` container joins the tailnet as **`luna`** and acts as a subnet
router (advertising `192.168.31.0/24`) and opt-in exit node. This is how other
people reach Jellyfin at `luna:8096` and Jellyseerr at `luna:5055`.

Exposed ports are declared in [`tailscale/serve.json`](tailscale/serve.json),
applied by containerboot on startup. Two constraints worth knowing: the Mac's
LAN IP is hardcoded there (compose can't interpolate into a mounted file), so a
DHCP change means editing that file; and only services bound to *all* interfaces
work — anything on `127.0.0.1` is unreachable via the LAN IP.

### Public web — Cloudflare Tunnel
Services that need public ingress (no client required) are fronted by a **Cloudflare Tunnel**. Routes are configured in the Cloudflare Zero Trust dashboard; the local connector runs via `cloudflare-tunnel/docker-compose.yaml`.

## Installation

> Run once on a fresh machine. After that, use **Dockge** at `:5001` for day-to-day management.

**Prerequisites:** macOS, internet connection.

```bash
git clone https://github.com/jiwidi/homelab.git
cd homelab
./master_install.sh
```

The script will:
1. Install Homebrew, Colima, Docker, tmux if missing
2. Create a `.env` file (prompts for required secrets)
3. Start all services via their `install.sh` scripts

## Configuration

**Secrets are never committed.** `.env` files are gitignored repo-wide, as is any
directory named `config/` — which is what keeps `arr/config/` (gluetun's
WireGuard key, the \*arr `config.xml` API keys, qBittorrent credentials) out of
this public repo. Each stack ships a `.env.example` to copy:

```bash
cp arr/.env.example arr/.env && chmod 600 arr/.env
```

Repo-root `.env`:

| Variable | Purpose |
|----------|---------|
| `TWINGATE_NETWORK` | Twingate network name |
| `TWINGATE_ACCESS_TOKEN` | Connector access token from Twingate console |
| `TWINGATE_REFRESH_TOKEN` | Connector refresh token from Twingate console |
| `HOMEPAGE_AUTH_TOKEN` | Homepage auth token (auto-generated) |
| `SPEEDTEST_APP_KEY` | Speedtest app key (auto-generated) |
| `CLOUDFLARE_TUNNEL_TOKEN` | Connector token from Cloudflare Zero Trust |

Per-stack `.env` files (see each `.env.example`):

| File | Variables |
|------|-----------|
| `arr/.env` | `WIREGUARD_PRIVATE_KEY`, `WIREGUARD_ADDRESSES`, `MULLVAD_CITY`, `MEDIA_ROOT`, `PUID`, `PGID`, `TZ` |
| `tailscale/.env` | `TAILSCALE_AUTH_KEY` |
| `unsloth/.env` | `LLM_API_KEY` |

## Adding a Service

1. Create a directory with `docker-compose.yaml` and `install.sh`
2. Add any required env vars to `.env`
3. Run `bash <service>/install.sh` or use Dockge

Minimal `install.sh`:
```bash
#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
docker compose --file "$DIR/docker-compose.yaml" up -d
```

## Project Structure

```
homelab/
├── .env                  # Secrets (git-ignored)
├── .gitignore
├── master_install.sh     # One-time bootstrap script
│
├── arr/                  # Media automation (Prowlarr/Sonarr/Radarr/qBit/Jellyseerr)
├── tailscale/            # Tailnet subnet router + exit node (luna)
├── unsloth/              # Bare-metal LLM server (Apple Metal, no Docker)
│
├── dockge/               # Stack management UI
├── homepage/             # Dashboard + Glances + Speedtest
├── twingate/             # Private remote access connector
├── cloudflare-tunnel/    # Public ingress (Cloudflare Zero Trust)
├── ollama_openwebui/     # Open WebUI for llama-server
└── vert/                 # File converter
```

Jellyfin is not a directory here — it's a Homebrew cask installed on the host.

## License

MIT — see [LICENSE](LICENSE)
