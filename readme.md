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
| **Muse** | Discord music bot | — |
| **Vert** | File converter | 3002 |

### Bare-metal (no Docker)

| Service | Description | Port |
|---------|-------------|------|
| **llama-cpp** | Local LLM inference server (Apple Metal) | 8001 |

**Why not Docker?** Docker Desktop / Colima on macOS can't pass the Apple GPU through to containers, so Metal acceleration is unavailable inside containers. `llama.cpp` is built and run directly on the host to get full GPU acceleration. Open WebUI (in Docker) reaches it via `host.docker.internal:8001`.

Runs **Qwen3.6** via Unsloth GGUFs with the precise-coding sampling params from the Unsloth guide (thinking on, temp=0.6, top_p=0.95). Defaults to the dense **27B** (~15GB Q4) — smaller RAM footprint than the 35B-A3B MoE, leaving headroom for KV cache on a 32GB Mac. Exposes an Anthropic-compatible API on `:8001` for use with Claude Code.

Setup and run:
```bash
./llama-cpp/llama-server-setup.sh        # build llama.cpp with Metal
./llama-cpp/llama-server-start.sh        # default: 27b, thinking on
./llama-cpp/llama-server-start.sh 35b    # heavier MoE (higher quality, ~20GB)
./llama-cpp/llama-server-start.sh 27b off           # non-thinking general
./llama-cpp/llama-server-start.sh 27b budget=512    # thinking hard-capped at 512 tokens
```

Point Claude Code at it:
```bash
ANTHROPIC_BASE_URL=http://localhost:8001 ANTHROPIC_API_KEY=sk-no-key-required \
  claude --model unsloth/Qwen3.6-27B
```

### Game servers (on-demand)

Managed via CLI from the `games/` directory.

| Service | Port |
|---------|------|
| **Minecraft** (All the Mods 9) | 25565 |
| **Project Zomboid** | — |

## Remote Access

### Private (web UIs, SSH) — Twingate
Web UIs, management ports, and SSH are reached via **Twingate**. No ports are exposed to the internet. Install the Twingate client, authenticate, and reach services at their `localhost` address. Define a Resource per service in the Twingate admin console (e.g. `localhost:3000` for Homepage, `localhost:5001` for Dockge).

### Public web — Cloudflare Tunnel
Services that need public ingress (no client required) are fronted by a **Cloudflare Tunnel**. Routes are configured in the Cloudflare Zero Trust dashboard; the local connector runs via `cloudflare-tunnel/docker-compose.yaml`.

### Game servers — Playit
Game servers are exposed via **Playit** tunnels (`playit/`), so players don't need router port forwarding. Each game's container port is documented in its `docker-compose.yaml`.

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

Game servers are not auto-started — spin them up on demand:

```bash
docker compose -f games/hytale/docker-compose.yaml up -d
```

## Configuration

All secrets live in `.env` (git-ignored). Required variables:

| Variable | Purpose |
|----------|---------|
| `TWINGATE_NETWORK` | Twingate network name |
| `TWINGATE_ACCESS_TOKEN` | Connector access token from Twingate console |
| `TWINGATE_REFRESH_TOKEN` | Connector refresh token from Twingate console |
| `HOMEPAGE_AUTH_TOKEN` | Homepage auth token (auto-generated) |
| `SPEEDTEST_APP_KEY` | Speedtest app key (auto-generated) |
| `CLOUDFLARE_TUNNEL_TOKEN` | Connector token from Cloudflare Zero Trust |
| `PLAYIT_SECRET_KEY` | Agent secret from playit.gg |

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
├── dockge/               # Stack management UI
├── homepage/             # Dashboard + Glances + Speedtest
├── twingate/             # Private remote access connector
├── cloudflare-tunnel/    # Public ingress (Cloudflare Zero Trust)
├── playit/               # Game server tunnel (playit.gg)
├── ollama_openwebui/     # Open WebUI for llama-server
├── llama-cpp/            # Bare-metal LLM server (Apple Metal, no Docker)
├── muse/                 # Discord music bot
├── vert/                 # File converter
│
└── games/                # Game servers (managed via CLI)
    ├── minecraft/        # All the Mods 9
    └── zomboid/
```

## License

MIT — see [LICENSE](LICENSE)
