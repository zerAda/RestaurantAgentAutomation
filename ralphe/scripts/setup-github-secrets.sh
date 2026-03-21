#!/bin/bash
# =============================================================================
# Setup GitHub Secrets for CI/CD Pipeline
# =============================================================================
# Usage: ./setup-github-secrets.sh <github-repo> <ssh-key-path>
# Example: ./setup-github-secrets.sh myuser/resto-bot ~/.ssh/id_rsa
# =============================================================================

set -e

REPO=${1:-""}
SSH_KEY_PATH=${2:-"$HOME/.ssh/id_rsa"}

if [ -z "$REPO" ]; then
  echo "Usage: $0 <github-repo> [ssh-key-path]"
  echo "Example: $0 myuser/resto-bot ~/.ssh/id_rsa"
  exit 1
fi

echo "================================================"
echo "GitHub Secrets Setup for CI/CD Pipeline"
echo "================================================"
echo ""
echo "Repository: $REPO"
echo "SSH Key: $SSH_KEY_PATH"
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
  echo "ERROR: GitHub CLI (gh) is not installed"
  echo ""
  echo "Install it from: https://cli.github.com/"
  echo ""
  echo "Or manually add the secret in GitHub:"
  echo "  1. Go to https://github.com/$REPO/settings/secrets/actions"
  echo "  2. Click 'New repository secret'"
  echo "  3. Name: VPS_SSH_KEY"
  echo "  4. Value: (paste your SSH private key)"
  exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
  echo "Please authenticate with GitHub CLI first:"
  echo "  gh auth login"
  exit 1
fi

# Check SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "ERROR: SSH key not found at $SSH_KEY_PATH"
  exit 1
fi

echo "Setting VPS_SSH_KEY secret..."
gh secret set VPS_SSH_KEY --repo "$REPO" < "$SSH_KEY_PATH"
echo "VPS_SSH_KEY set successfully!"

echo ""
echo "================================================"
echo "Setup Complete!"
echo "================================================"
echo ""
echo "Your CI/CD pipeline is now configured."
echo ""
echo "Optional: Add ALERT_WEBHOOK_URL for notifications:"
echo "  gh secret set ALERT_WEBHOOK_URL --repo $REPO"
echo ""
echo "Test the pipeline:"
echo "  1. Push to main branch"
echo "  2. Go to https://github.com/$REPO/actions"
echo "  3. Watch the CI pipeline run"
echo ""
