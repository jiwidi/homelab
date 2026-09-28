# My Personal Homelab

Docker configurations and install scripts for my personal homelab, running on
**sol** (Debian 13). It previously ran on a Mac Mini M4 (`luna`); the macOS-only
parts (Colima, Metal LLM server, native Jellyfin) are noted as such below.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Hardware

- **sol** — 28 threads, 62 GB RAM, Intel UHD 770 iGPU, 3.5 TB NVMe `/home`. Debian 13.
  LAN `192.168.2.92` on the UniFi `gamelab` network (isolated from `galaxy`).
- **truenas** — `192.168.1.60` on `galaxy`. Runs the media stack (Jellyfin,
  Seerr, Sonarr/Radarr/Bazarr/Prowlarr, Transmission) and the SMB shares.
- *(retired)* **luna** — Mac Mini M4, 32 GB RAM, `192.168.1.169`.

## Boot / crash recovery

Docker and containerd are enabled systemd units, and every service uses
`restart: unless-stopped`, so after a power loss or crash every stack comes back
by itself. The one exception is by design: a stack you stopped yourself
(`docker compose stop`, or Stop in Dockge) stays stopped across reboots —
`start` it again to re-enable. Game servers live in the separate
[gamelab](https://github.com/jiwidi/gamelab) repo and follow the same rule.

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

### Tailnet — Tailscale
The `tailscale/` container runs in host network mode, so **sol itself** is the
tailnet node `sol`: every port on it is reachable at `sol:<port>`. It also
advertises a subnet route to the NAS only (`192.168.1.60/32`), putting every
NAS port — SMB, TrueNAS UI, Jellyfin, Seerr, the \*arrs — at
`192.168.1.60:<port>` from anywhere on the tailnet, plus an opt-in exit node.
Needs a UniFi rule allowing sol → NAS; see
[`tailscale/README.md`](tailscale/README.md).

### Public web — Cloudflare Tunnel
Services that need public ingress (no client required) are fronted by a **Cloudflare Tunnel**. Routes are configured in the Cloudflare Zero Trust dashboard; the local connector runs via `cloudflare-tunnel/docker-compose.yaml`.

## Installation

> Run once on a fresh machine. After that, use **Dockge** at `:5001` for day-to-day management.

**Prerequisites:** Docker Engine + compose plugin (`master_install.sh` is still
the macOS/Homebrew bootstrap; on Linux, run each stack's `install.sh` directly).

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
