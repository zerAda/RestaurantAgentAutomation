#!/bin/bash
# =============================================================================
# VPS Auto-Provisioning & Security Hardening Script (Pro One standard)
# =============================================================================
#
# USAGE:
#   Log in to the fresh VPS as root.
#   Upload this script: scp provision_vps.sh root@<IP>:/root/
#   Run: chmod +x provision_vps.sh && ./provision_vps.sh
#
# WHAT IT DOES:
#   1. System Update & Upgrade
#   2. Installs Docker & Docker Compose Plugin
#   3. Creates 'deploy' user with ssh key access (locked down password)
#   4. Sets up application directory structure
#   5. Configures UFW (Firewall)
#   6. Installs and configures Fail2ban
#   7. Hardens SSH (Disables root login & password auth)
# =============================================================================

set -e

echo "====================================================="
echo "  Resto Bot Pro One VPS Provisioning Starting..."
echo "====================================================="

# Must run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

DEBIAN_FRONTEND=noninteractive

# 1. Update & Base Tools
echo "==> Updating System & Installing Base Tools..."
apt-get update -yq && apt-get upgrade -yq
apt-get install -yq curl wget git ufw fail2ban rsync jq make

# 2. Install Docker
echo "==> Installing Docker Engine..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
else
    echo "Docker already installed, skipping."
fi

# Ensure docker compose plugin is installed
apt-get install -yq docker-compose-plugin

# 3. Setup 'deploy' user
echo "==> Setting up 'deploy' user..."
if ! id "deploy" &>/dev/null; then
    useradd -m -s /bin/bash deploy
    usermod -aG docker deploy
    
    # Generate random complex password (we won't use it, SSH keys only)
    RAND_PASS=$(openssl rand -base64 32)
    echo "deploy:$RAND_PASS" | chpasswd
    
    # Setup SSH directory
    mkdir -p /home/deploy/.ssh
    if [ -f /root/.ssh/authorized_keys ]; then
        cp /root/.ssh/authorized_keys /home/deploy/.ssh/
    fi
    chmod 700 /home/deploy/.ssh
    chmod 600 /home/deploy/.ssh/authorized_keys
    chown -R deploy:deploy /home/deploy/.ssh
else
    echo "User 'deploy' already exists. Ensuring docker group and permissions..."
    usermod -aG docker deploy
    chown -R deploy:deploy /home/deploy/.ssh || true
fi

# 4. Directory Structure
echo "==> Creating Application Directory Structure..."
PROJECT_DIR="/opt/resto"
mkdir -p "$PROJECT_DIR/releases"
mkdir -p "$PROJECT_DIR/shared/secrets"
mkdir -p "$PROJECT_DIR/backups"
mkdir -p "/var/log/resto-bot"

chown -R deploy:deploy "$PROJECT_DIR"
chown -R deploy:deploy "/var/log/resto-bot"

# 5. UFW Firewall Setup
echo "==> Configuring UFW Firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp  # SSH
ufw allow 80/tcp  # HTTP
ufw allow 443/tcp # HTTPS
echo "y" | ufw enable

# 6. Fail2ban Setup
echo "==> Configuring Fail2ban..."
cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 3600
EOF
systemctl restart fail2ban
systemctl enable fail2ban

# 7. SSH Hardening
echo "==> Hardening SSH Configuration..."
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/g' /etc/ssh/sshd_config
# Reload SSH gracefully (Debian/Ubuntu usually has ssh or sshd service)
systemctl reload sshd || systemctl reload ssh

echo "====================================================="
echo "  ✅ VPS Provisioning Complete!"
echo "  Your instance is secured and ready for deployments."
echo ""
echo "  NEXT STEPS:"
echo "  1. Test SSH connection: ssh deploy@<VPS_IP>"
echo "  2. Exit this session"
echo "====================================================="
