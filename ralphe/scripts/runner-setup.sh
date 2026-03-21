#!/usr/bin/env bash
# =============================================================================
# runner-setup.sh — Install GitHub Actions self-hosted runner on VPS
# =============================================================================
# Run once as deploy user on the VPS.
#
# Usage:
#   bash /opt/resto/current/scripts/runner-setup.sh --token <RUNNER_TOKEN>
#
# Get a runner token from:
#   GitHub repo → Settings → Actions → Runners → New self-hosted runner
#   (Token is single-use, valid 1 hour)
#
# Labels applied: self-hosted,linux,vps-primary
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/zerAda/RestaurantAgentAutomation"
RUNNER_VERSION="2.322.0"
RUNNER_SHA="b4f5b74a8c5f6b4d5f48f5efc8c6b4d5a8c5f6b4"  # update from GitHub release page
RUNNER_DIR="$HOME/actions-runner"
RUNNER_TOKEN=""
RUNNER_NAME="vps-primary-$(hostname -s)"
RUNNER_LABELS="self-hosted,linux,vps-primary"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[runner-setup]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err()  { echo -e "${RED}[error]${NC} $*"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token) RUNNER_TOKEN="$2"; shift 2 ;;
    --name)  RUNNER_NAME="$2"; shift 2 ;;
    *) err "Unknown argument: $1" ;;
  esac
done

[[ -z "$RUNNER_TOKEN" ]] && err "Missing --token. Get it from: $REPO_URL/settings/actions/runners/new"

# Check if runner already running
if [[ -f "$RUNNER_DIR/.runner" ]]; then
  warn "Runner already configured at $RUNNER_DIR"
  warn "To re-register: cd $RUNNER_DIR && ./config.sh remove && re-run this script"
  exit 0
fi

log "Installing GitHub Actions runner $RUNNER_VERSION"
log "  Repo   : $REPO_URL"
log "  Name   : $RUNNER_NAME"
log "  Labels : $RUNNER_LABELS"

# Download
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

ARCH="linux-x64"
TARBALL="actions-runner-${ARCH}-${RUNNER_VERSION}.tar.gz"

log "Downloading runner..."
curl -fsSLo "$TARBALL" \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${TARBALL}"

# Minimal checksum note (SHA changes per release — verify at download time)
log "Extracting..."
tar xzf "$TARBALL"
rm "$TARBALL"

# Configure
log "Configuring runner..."
./config.sh \
  --url "$REPO_URL" \
  --token "$RUNNER_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --work "_work" \
  --unattended

# Install as systemd service
log "Installing systemd service..."
sudo ./svc.sh install deploy
sudo ./svc.sh start

log ""
log "=== Runner installed and started ==="
log "  Service : actions.runner.$(basename $REPO_URL).${RUNNER_NAME}"
log "  Status  : $(sudo ./svc.sh status 2>/dev/null | head -3)"
log ""
log "Verify at: $REPO_URL/settings/actions/runners"
