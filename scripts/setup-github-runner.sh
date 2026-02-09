#!/bin/bash
# ===========================================
# GitHub Actions Self-Hosted Runner Setup
# For: Resto Bot VPS Deployment
# ===========================================

set -euo pipefail

# Configuration
REPO_URL="https://github.com/zerAda/RestaurantAgentAutomation"
RUNNER_DIR="$HOME/actions-runner"
PROJECT_DIR="/opt/resto-bot"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "========================================"
echo "  GitHub Self-Hosted Runner Setup"
echo "  Resto Bot CI/CD"
echo "========================================"
echo -e "${NC}"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo -e "${YELLOW}WARNING: Running as root. Runner will be configured for root user.${NC}"
    echo "For security, consider running as a non-root user."
    read -p "Continue anyway? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
    x86_64)  ARCH="x64" ;;
    aarch64) ARCH="arm64" ;;
    arm64)   ARCH="arm64" ;;
    *)       echo -e "${RED}Unsupported architecture: $ARCH${NC}"; exit 1 ;;
esac

echo -e "${GREEN}Detected: ${OS}-${ARCH}${NC}"
echo ""

# Step 1: Install dependencies
echo -e "${BLUE}[1/6] Installing dependencies...${NC}"

if command -v apt-get &>/dev/null; then
    sudo apt-get update
    sudo apt-get install -y curl jq tar rsync docker.io docker-compose-plugin

    # Add user to docker group
    sudo usermod -aG docker $USER 2>/dev/null || true

elif command -v yum &>/dev/null; then
    sudo yum install -y curl jq tar rsync docker docker-compose-plugin
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker $USER 2>/dev/null || true

else
    echo -e "${YELLOW}Please install manually: curl, jq, tar, rsync, docker${NC}"
fi

echo -e "${GREEN}Dependencies installed${NC}"
echo ""

# Step 2: Create project directory
echo -e "${BLUE}[2/6] Creating project directory...${NC}"

sudo mkdir -p "$PROJECT_DIR"
sudo mkdir -p "$PROJECT_DIR-backups"
sudo chown -R $USER:$USER "$PROJECT_DIR"
sudo chown -R $USER:$USER "$PROJECT_DIR-backups"

echo -e "${GREEN}Project directory: $PROJECT_DIR${NC}"
echo ""

# Step 3: Download runner
echo -e "${BLUE}[3/6] Downloading GitHub Actions runner...${NC}"

mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# Get latest version
LATEST_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
echo "Latest version: $LATEST_VERSION"

RUNNER_FILE="actions-runner-${OS}-${ARCH}-${LATEST_VERSION}.tar.gz"
DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${LATEST_VERSION}/${RUNNER_FILE}"

if [[ ! -f "config.sh" ]]; then
    echo "Downloading runner..."
    curl -L -o "$RUNNER_FILE" "$DOWNLOAD_URL"

    echo "Extracting..."
    tar xzf "$RUNNER_FILE"
    rm "$RUNNER_FILE"
else
    echo "Runner already downloaded"
fi

echo -e "${GREEN}Runner ready in: $RUNNER_DIR${NC}"
echo ""

# Step 4: Get runner token
echo -e "${BLUE}[4/6] Runner Registration${NC}"
echo ""
echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW}MANUAL STEP REQUIRED${NC}"
echo -e "${YELLOW}============================================${NC}"
echo ""
echo "1. Go to: ${REPO_URL}/settings/actions/runners/new"
echo ""
echo "2. Copy the token shown in the 'Configure' section"
echo "   (It looks like: AXXXXXXXXXXXXXXXXXXXX)"
echo ""
read -p "Paste your runner token here: " RUNNER_TOKEN

if [[ -z "$RUNNER_TOKEN" ]]; then
    echo -e "${RED}No token provided. Exiting.${NC}"
    exit 1
fi

# Step 5: Configure runner
echo -e "${BLUE}[5/6] Configuring runner...${NC}"

cd "$RUNNER_DIR"

# Remove old config if exists
if [[ -f ".runner" ]]; then
    echo "Removing old configuration..."
    ./config.sh remove --token "$RUNNER_TOKEN" 2>/dev/null || true
fi

# Configure new runner
./config.sh \
    --url "$REPO_URL" \
    --token "$RUNNER_TOKEN" \
    --name "resto-bot-vps-$(hostname)" \
    --labels "self-hosted,linux,resto-bot,vps" \
    --work "_work" \
    --unattended \
    --replace

echo -e "${GREEN}Runner configured${NC}"
echo ""

# Step 6: Install as service
echo -e "${BLUE}[6/6] Installing runner as service...${NC}"

sudo ./svc.sh install
sudo ./svc.sh start

echo ""
echo -e "${GREEN}========================================"
echo "  SETUP COMPLETE!"
echo "========================================${NC}"
echo ""
echo "Runner Status:"
sudo ./svc.sh status
echo ""
echo -e "${BLUE}Project Directory:${NC} $PROJECT_DIR"
echo -e "${BLUE}Runner Directory:${NC}  $RUNNER_DIR"
echo -e "${BLUE}Backups Directory:${NC} $PROJECT_DIR-backups"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Push code to GitHub to trigger deployment"
echo "2. Monitor at: ${REPO_URL}/actions"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  View runner logs:  sudo journalctl -u actions.runner.*"
echo "  Restart runner:    cd $RUNNER_DIR && sudo ./svc.sh restart"
echo "  View stack logs:   cd $PROJECT_DIR && docker compose -f docker-compose.hostinger.prod.yml logs -f"
echo ""
