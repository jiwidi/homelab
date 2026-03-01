# My Personal Homelab

Docker configurations and install scripts for my personal homelab on a Mac Mini M4.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## Hardware

- **Mac Mini M4** — Apple M4, 32GB RAM, [2TB custom Chinese NVMe](https://item.taobao.com/item.htm?abbucket=14&id=874377707144&ns=1&priceTId=2100c80417368883046408893e0be2&skuId=5882661866398&spm=a21n57.1.hoverItem.2&utparam=%7B%22aplus_abtest%22%3A%22741a06251058619e3d5eda8db6a4078b%22%7D&xxc=taobaoSearch) replacing the internal 256GB SSD

## Services

### Always-on

| Service | Description | Port |
|---------|-------------|------|
| **Dockge** | Compose stack management UI | 5001 |
| **Homepage** | Dashboard | 3000 |
| **Speedtest Tracker** | Internet speed monitoring | 8081 |
| **Glances** | System monitoring | 61208 |
| **Twingate** | Remote access connector | — |
| **Muse** | Discord music bot | — |
| **Vert** | File converter | 3002 |

### Game servers (on-demand)

Managed via CLI from the `games/` directory.

| Service | Port |
|---------|------|
| **Project Zomboid** | — |

## Remote Access

### Web services & management — Twingate

Web UIs, management ports, and SSH are accessed via **Twingate**. No ports are exposed to the internet. Install the Twingate client, authenticate, and reach services directly at their `localhost` address.

Define Resources in the Twingate admin console for each service you want to access remotely (e.g. `localhost:3000` for Homepage, `localhost:5001` for Dockge).

### Game servers — port forwarding

Game servers are not routed through Twingate. Players connect directly via router port forwarding. Each game's port is documented in its `docker-compose.yaml`.

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
├── twingate/             # Remote access connector
├── muse/                 # Discord music bot
├── vert/                 # File converter
│
└── games/                # Game servers (managed via CLI)
    └── zomboid/
```

## License

MIT — see [LICENSE](LICENSE)
