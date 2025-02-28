#!/bin/bash
set -e

# Color setup
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Homelab Server Installation Script    ${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check for brew; install if missing.
if ! command -v brew >/dev/null; then
  echo -e "${YELLOW}Homebrew not found. Installing Homebrew...${NC}"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo >> ~/.zprofile
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  echo -e "${GREEN}Homebrew is already installed.${NC}"
fi

# Check for Docker; install if missing.
if ! command -v docker >/dev/null; then
  echo -e "${YELLOW}Docker not found. Installing Docker...${NC}"
  brew install docker
else
  echo -e "${GREEN}Docker is already installed.${NC}"
fi

# Check for tmux
if ! command -v tmux >/dev/null; then
  echo -e "${YELLOW}tmux not found. Installing tmux...${NC}"
  brew install tmux
else
  echo -e "${GREEN}tmux is already installed.${NC}"
fi

# Load secrets from .env if it exists or create it
ENV_FILE="$(dirname "$0")/.env"

if [ -f "$ENV_FILE" ]; then
  echo -e "${GREEN}Loading secrets from .env file...${NC}"
  source "$ENV_FILE"
else
  echo -e "${YELLOW}No .env file found. Creating one with default values...${NC}"

  # Create .env file with prompts for required secrets
  echo -e "${BLUE}Please provide the following configuration values:${NC}"

  # Cloudflare
  read -p "Cloudflare Tunnel Token: " CLOUDFLARE_TUNNEL_TOKEN

  # Homepage
  read -p "Homepage AUTH_TOKEN (press Enter for random): " HOMEPAGE_AUTH_TOKEN
  if [ -z "$HOMEPAGE_AUTH_TOKEN" ]; then
    HOMEPAGE_AUTH_TOKEN=$(openssl rand -base64 32)
    echo -e "${GREEN}Generated random Homepage AUTH_TOKEN${NC}"
  fi

  # Speed Test Tracker
  read -p "Speedtest APP_KEY (press Enter for random): " SPEEDTEST_APP_KEY
  if [ -z "$SPEEDTEST_APP_KEY" ]; then
    SPEEDTEST_APP_KEY=$(openssl rand -base64 32)
    echo -e "${GREEN}Generated random Speedtest APP_KEY${NC}"
  fi

  # Plex
  read -p "Plex Claim Token (get from https://plex.tv/claim): " PLEX_CLAIM

  # qBittorrent
  read -p "qBittorrent WebUI Username [admin]: " WEBUI_USERNAME
  WEBUI_USERNAME=${WEBUI_USERNAME:-admin}

  read -s -p "qBittorrent WebUI Password [adminadmin]: " WEBUI_PASSWORD
  echo
  WEBUI_PASSWORD=${WEBUI_PASSWORD:-adminadmin}

  # Create .env file
  cat > "$ENV_FILE" <<EOL
# Cloudflare
CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}

# Homepage/Speedtest
HOMEPAGE_AUTH_TOKEN=${HOMEPAGE_AUTH_TOKEN}
SPEEDTEST_APP_KEY=${SPEEDTEST_APP_KEY}

# Plex
PLEX_CLAIM=${PLEX_CLAIM}

# qBittorrent
WEBUI_USERNAME=${WEBUI_USERNAME}
WEBUI_PASSWORD=${WEBUI_PASSWORD}
EOL

  echo -e "${GREEN}.env file created successfully${NC}"
  echo -e "${YELLOW}NOTE: Add .env to your .gitignore file to keep your secrets safe${NC}"

  # Make sure .env is in .gitignore
  if ! grep -q "^.env$" "$(dirname "$0")/.gitignore" 2>/dev/null; then
    echo ".env" >> "$(dirname "$0")/.gitignore"
    echo -e "${GREEN}Added .env to .gitignore${NC}"
  fi
fi

# Define the source folder containing all services.
SRC_DIR="$(dirname "$0")/"

# Export all variables from .env for use in docker-compose files
export $(grep -v '^#' "$ENV_FILE" | xargs)

# Iterate over each service folder
echo -e "${BLUE}Installing services...${NC}"
for service in "$SRC_DIR"/*; do
  if [ -d "$service" ] && [ -f "$service/install.sh" ]; then
    SERVICE_NAME=$(basename "$service")
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${YELLOW}Spinning $SERVICE_NAME...${NC}"

    # Execute the service's install script with environment variables
    bash "$service/install.sh"

    echo -e "${GREEN}$SERVICE_NAME installed successfully${NC}"
  fi
done

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}All services have been installed successfully!${NC}"
echo -e "${YELLOW}Tips:${NC}"
echo -e "  - To view running containers: ${BLUE}docker ps${NC}"
echo -e "  - Access your dashboard at: ${BLUE}http://localhost:3000${NC}"
echo -e "  - Portainer is available at: ${BLUE}http://localhost:9000${NC}"
echo -e "${BLUE}=========================================${NC}"