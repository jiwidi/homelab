# 🏠 My Personal Homelab

This repository contains the Docker configurations and installation scripts that power my personal homelab server. I've decided to share my setup publicly in case others find it useful for their own homelab projects.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## 💻 Hardware

My current homelab runs on:
- **Mac Mini M4**
- **CPU**: Apple M4 chipset
- **RAM**: 32GB
- **Storage**: [2TB custom Chinese NVMe](https://item.taobao.com/item.htm?abbucket=14&id=874377707144&ns=1&priceTId=2100c80417368883046408893e0be2&skuId=5882661866398&spm=a21n57.1.hoverItem.2&utparam=%7B%22aplus_abtest%22%3A%22741a06251058619e3d5eda8db6a4078b%22%7D&xxc=taobaoSearch) replaced the internal 256GB SSD. Video

The entire setup is compact, energy-efficient, and powerful enough to run all my services simultaneously without breaking a sweat. All while being silent and having a small size footprint.

## 🧩 Services

Here's what's currently running in my homelab:

| Service | Description | Port | URL |
|---------|-------------|------|-----|
| **Homepage** | Main dashboard for all services | 3000 | http://localhost:3000 |
| **Portainer** | Docker container management | 9000 | http://localhost:9000 |
| **Cloudflare Tunnel** | Secure remote access | N/A | Various subdomains |
| **Tailscale** | VPN for secure remote access | N/A | Via Tailscale client |
| **Glances** | System monitoring | 61208 | http://localhost:61208 |
| **qBittorrent** | Torrent client | 8082 | http://localhost:8082 |
| **Plex** | Media server | Host networking | http://localhost:32400/web |
| **Excalidraw** | Collaborative drawing tool | 3030 | http://localhost:3030 |
| **Ollama + OpenWebUI** | Self-hosted AI/LLM service | 8083 | http://localhost:8083 |
| **Speedtest Tracker** | Internet speed monitoring | 8081 | http://localhost:8081 |

## 🚀 Installation

### Prerequisites

- macOS system (the script uses Homebrew for dependencies)
- Internet connection
- If you want to replicate my exact setup: a Mac with Apple Silicon

### Setup Process

1. Clone this repository:
   ```bash
   git clone https://github.com/jiwidi/homelab-server.git
   cd homelab-server
   ```

2. Run the master installation script:
   ```bash
   ./master_install.sh
   ```

3. Follow the interactive prompts to configure your environment.

## 🔧 Script Explanation

### `master_install.sh`

This is the main orchestration script that:

1. **Checks and installs dependencies** (Homebrew, Docker, tmux)
2. **Manages configuration** through a `.env` file
3. **Sets up all services** by iterating through each directory and running individual installation scripts

The script is designed to be idempotent - you can run it multiple times without issues. It will only install dependencies if they're missing and will respect existing configurations.

### Service-specific scripts

Each service directory contains:
- `docker-compose.yaml` - Container configuration
- `install.sh` - Service-specific installation script

These modular scripts allow for easier maintenance and give you the flexibility to add or remove services.

## ⚙️ Configuration

### Environment Variables

I use a `.env` file for all sensitive configuration to avoid hardcoding secrets in the repository. The master install script will create this file if it doesn't exist, prompting you for values or generating secure defaults.

Key variables include:

| Variable | Purpose | Default |
|----------|---------|---------|
| `CLOUDFLARE_TUNNEL_TOKEN` | Token for Cloudflare Tunnel | (user provided) |
| `HOMEPAGE_AUTH_TOKEN` | Homepage dashboard auth token | (randomly generated) |
| `SPEEDTEST_APP_KEY` | Speedtest app auth key | (randomly generated) |
| `PLEX_CLAIM` | Plex claim token | (user provided) |
| `WEBUI_USERNAME` | qBittorrent username | admin |
| `WEBUI_PASSWORD` | qBittorrent password | adminadmin |
| `TAILSCALE_AUTH_KEY` | Tailscale authentication key | (user provided) |

A `.env.example` file is included as a reference.

## 🔒 Security

Security was a priority when designing this setup:

- **No hardcoded secrets** - All sensitive information lives in the `.env` file (excluded from git)
- **Minimal permissions** - Docker containers run with the minimum required access
- **Safe Docker socket access** - Socket is exposed securely to prevent unauthorized container access
- **Automatic secret generation** - The script can generate secure random tokens for services
- **VPN Access** - Tailscale provides secure access without exposing services directly to the internet

## 📁 Project Structure

```
homelab-server/
├── .env                  # Your environment variables (not committed)
├── .env.example          # Example environment variables
├── .gitignore            # Git ignore file (includes .env)
├── LICENSE               # MIT License
├── README.md             # This file
├── master_install.sh     # Main installation script
│
├── cloudfare/            # Cloudflare tunnel configuration
│   ├── docker-compose.yaml
│   └── install.sh
│
├── excalidraw/           # Excalidraw drawing tool
│   ├── docker-compose.yaml
│   └── install.sh
│
├── homepage/             # Homepage dashboard
│   ├── docker-compose.yaml
│   └── install.sh
│
├── ollama_openwbui/      # Ollama and OpenWebUI
│   ├── docker-compose.yaml
│   └── install.sh
│
├── plex/                 # Plex media server
│   ├── docker-compose.yaml
│   └── install.sh
│
├── portainer/            # Portainer container management
│   ├── docker-compose.yaml
│   └── install.sh
│
├── qbittorrent/          # qBittorrent torrent client
│   ├── docker-compose.yaml
│   └── install.sh
│
└── tailscale/            # Tailscale VPN for remote access
    ├── docker-compose.yaml
    ├── install.sh
    └── README.md         # Tailscale-specific documentation
```

## 🧰 Expandability

One of the key design principles of this setup is easy expandability:

### Adding a New Service

1. Create a new directory for your service
2. Add a `docker-compose.yaml` file
3. Create an `install.sh` script (see existing ones as examples)
4. Update the main `.env` file if your service needs additional environment variables

Example `install.sh` template:
```bash
#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
docker-compose -f "$DIR/docker-compose.yaml" up -d
```

### Personal Customizations

I've made several customizations for my specific needs:

- **Media Management**: Plex is configured to use my `~/Videos` directory for media
- **Swedish Timezone**: Services are configured for Europe/Stockholm timezone
- **Cloudflare Tunnels**: Set up for my domain (jiwidi.com) and subdomains

Feel free to adjust these settings in the docker-compose files to match your requirements.

## 🌐 Remote Access

I provide two options for remote access to my homelab:

### Cloudflare Tunnels

For public-facing services, I use Cloudflare Tunnels on the free tier. This allows me to expose specific services through a secure tunnel without opening ports on my router.

To use this feature with your own domain:
1. Create a Cloudflare account
2. Set up a tunnel for your domain
3. Update the `CLOUDFLARE_TUNNEL_TOKEN` in your `.env` file

### Tailscale VPN

For more secure, private access to all services, I use Tailscale. This mesh VPN allows me to connect to my homelab from anywhere without exposing services directly to the internet.

Key features:
- **Zero configuration** networking - no port forwarding needed
- **End-to-end encryption** for all traffic
- **Access control** through Tailscale's admin console
- **Exit node capability** - route all your internet traffic through your home connection when on public WiFi

Setup:
1. Create a Tailscale account at [https://tailscale.com/](https://tailscale.com/)
2. Generate an auth key in the admin console
3. Add the key to your `.env` file as `TAILSCALE_AUTH_KEY`
4. Run the installation script

Once set up, you can connect to your homelab services using the Tailscale IP address from any device with the Tailscale client installed.

## 🤖 Development Notes

This is an ongoing project, and I'm continually refining and adding services. Some things I'm considering for the future:

- Home automation integration
- NAS functionality with an external 4 NVMe drive enclosure
- Enhanced backup solutions

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.