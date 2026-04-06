# CI/CD Runbook - Resto Bot

> Last updated: 2026-04-06

## Overview

This document describes the GitHub Actions workflows for Resto Bot production operations.

| Workflow | Purpose | Trigger | Runner |
|----------|---------|---------|--------|
| **Build and Push Artifacts** (`build-push-artifacts.yml`) | Build Docker images → GHCR | Push to `main` | `ubuntu-latest` |
| **CD - Deploy to VPS** (`cd-deploy.yml`) | Full CD diamond: validate→preflight→security-gate→staging→smoke→approve→backup→deploy→dora→cleanup | `workflow_run` (Build success on main) or `workflow_dispatch` | `[self-hosted, vps-primary]` |
| **CI** (`ci.yml`) | Lint, test, smoke-routing | Push/PR | `ubuntu-latest` |
| **Health Monitor** (`health-monitor.yml`) | Check n8n availability | Every 6 hours | `ubuntu-latest` |
| **Scheduled Backup** (`scheduled-backup.yml`) | PostgreSQL backup | Daily 3AM, Weekly 4AM | `[self-hosted, vps-primary]` |
| **Security Scan** (`security-scan.yml`) | Gitleaks + Trivy + SBOM | Push/PR | `ubuntu-latest` |
| **CD - Deploy to VPS (manual)** (`ralphe-cd-deploy.yml`) | Manual deploy only | `workflow_dispatch` only | `[self-hosted, vps-primary]` |

### CD Diamond Pipeline

```
Build (ubuntu-latest)
  └─► CD triggered via workflow_run
        ├─ validate-inputs
        ├─ preflight (self-hosted)
        ├─ security-gate (ubuntu-latest)
        ├─ deploy-staging (self-hosted) ──── staging smoke tests
        ├─ smoke-battery-staging (self-hosted)
        ├─ approve-production (environment: production)
        ├─ backup (self-hosted, skipped on is_first_deploy)
        ├─ deploy-production (self-hosted) ─── deploy_to_node.sh
        ├─ dora (self-hosted)
        └─ cleanup
```

### Known Fixes Applied (2026-04-06)

| Issue | Fix | Commit |
|-------|-----|--------|
| Duplicate auto-trigger in `ralphe-cd-deploy.yml` blocked `deploy-production` concurrency slot | Removed `workflow_run:` trigger; keep `workflow_dispatch:` only | 358ea78 |
| nginx CI service health check always failed (`8080:8080` vs port 80 inside container) | Changed to `8080:80` + `curl localhost/` | 358ea78 |
| Backup selected staging postgres container when both ran concurrently | Filter by compose project label to prefer production container | 10c2205 |
| `cd-deploy.yml` packages permission missing for GHCR pull | Added `packages: read` | 10c2205 |
| Secret bind-mounts missing on re-deploys (created on first deploy only) | Create all 5 files on every deploy with `if [ ! -f ]` guards | 658dc2a |
| External Docker volumes missing on re-deploys (created on first deploy only) | Create all 6 volumes on every deploy with `2>/dev/null \|\| true` | 81ddd7a |
| `mkdir -p /var/log/resto-bot` fails for deploy user → kills script in 21s | Fallback to `$PROJECT_DIR/logs` + ERR trap for line-level diagnostics | f344190 |

---

## Required Configuration

### Repository Variables (Settings > Variables)

| Variable | Description | Default used by CD | Notes |
|----------|-------------|-------------------|-------|
| `VPS_HOST` | VPS IP address | Required | SSH target for all self-hosted jobs |
| `VPS_USER` | SSH username | `deploy` | Must be in docker group |
| `PROJECT_DIR` | Deployment root on VPS | `/opt/resto` | Releases stored at `$PROJECT_DIR/releases/` |
| `BACKUP_DIR` | Backup storage directory | `$PROJECT_DIR/backups` | Postgres dumps stored here |
| `LOG_DIR` | Log directory | `/var/log/resto-bot` | Falls back to `$PROJECT_DIR/logs` if not writable |
| `DOMAIN` | Production domain | — | Used for Traefik routing rules |
| `HEALTH_URL` | Public health endpoint URL | `https://api.<DOMAIN>/healthz` | Must be the public nginx gateway, not Traefik console |
| `ADMIN_ALLOWED_IPS` | Traefik/Adminer/n8n console IP allowlist | — | CIDR ranges |

### Repository Secrets (Settings > Secrets)

| Secret | Required For | Description |
|--------|--------------|-------------|
| `VPS_SSH_KEY` | All self-hosted CD jobs | SSH private key (ed25519 recommended) for `VPS_USER@VPS_HOST` |
| `ALERT_WEBHOOK_URL` | Health alerts, DORA | Slack/Discord webhook URL (optional) |
| `S3_ACCESS_KEY_ID` | Off-site backup | S3-compatible storage key ID |
| `S3_SECRET_ACCESS_KEY` | Off-site backup | S3-compatible storage secret |
| `BACKUP_GPG_PASSPHRASE` | Off-site backup | GPG AES-256 encryption passphrase for backup archives |

---

## Health Monitor Workflow

### How It Works

1. **HTTP Check**: Sends GET request to `HEALTH_URL`
2. **SSH Diagnostics**: If HTTP fails AND `VPS_SSH_KEY` is configured, runs internal checks
3. **Alert**: If unhealthy AND `ALERT_WEBHOOK_URL` is configured, sends notification

### Critical: HEALTH_URL Configuration

```
CORRECT:   https://api.<domain>/healthz     (Public gateway, no auth)
WRONG:     https://n8n.<domain>/healthz     (Console, IP-protected -> 403)
WRONG:     https://console.<domain>/healthz (Console, IP-protected -> 403)
```

The `/healthz` endpoint is served by the nginx gateway (line 65-68 of `infra/gateway/nginx.conf`), which is exposed on the `api.<domain>` subdomain without IP allowlist protection.

### Status Codes Meaning

| Status | HTTP Code | Meaning | Action |
|--------|-----------|---------|--------|
| `healthy` | 200 | All good | None |
| `unreachable` | 000 | Connection failed | Check DNS, VPS status |
| `auth_blocked` | 401/403 | IP blocked | Change HEALTH_URL to API gateway |
| `backend_down` | 502/503/504 | Container crashed | SSH and restart containers |

### Manual Trigger

```bash
# Via GitHub CLI
gh workflow run "Health Monitor" --ref main

# With forced SSH check
gh workflow run "Health Monitor" --ref main -f force_ssh_check=true
```

### Troubleshooting Health Check Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| Always 403 | URL points to protected console | Set `HEALTH_URL` to `https://api.<domain>/healthz` |
| Always 000 | DNS issue or VPS down | Check VPS status in Hostinger panel |
| 502/503 | n8n container crashed | SSH: `docker compose restart n8n-main` |
| Intermittent failures | Rate limiting | Reduce check frequency |

---

## Scheduled Backup Workflow

### How It Works

1. **Prerequisites Check**: Validates SSH key is configured
2. **Pre-checks**: Verifies VPS is ready (disk, postgres, docker)
3. **Backup**: Creates pg_dump + config archive
4. **Verify**: Tests backup integrity with gunzip -t
5. **Rotate**: Removes old backups (daily: 7 days, weekly: 4 weeks)

### Backup Types

| Type | Schedule | Retention |
|------|----------|-----------|
| Daily | 3:00 AM UTC | 7 days |
| Weekly (full) | Sunday 4:00 AM UTC | 4 weeks |

### Backup Files Created

```
/local-files/backups/resto-bot/
├── daily-20240115-030000-db.dump.gz      # PostgreSQL dump (compressed)
├── daily-20240115-030000-config.tar.gz   # .env + secrets/
├── daily-20240115-030000-metadata.txt    # Backup info
└── ...
```

### Manual Trigger

```bash
# Daily backup
gh workflow run "Scheduled Backup" --ref main -f backup_type=daily

# Full backup
gh workflow run "Scheduled Backup" --ref main -f backup_type=full

# Skip pre-checks (debugging)
gh workflow run "Scheduled Backup" --ref main -f backup_type=daily -f skip_prechecks=true
```

### Pre-check Failures

| Error | Cause | Fix |
|-------|-------|-----|
| `PROJECT_DIR_NOT_FOUND` | Wrong path | Check `PROJECT_DIR` variable |
| `NO_COMPOSE_FILE` | Missing docker-compose | Deploy project to VPS |
| `DOCKER_NOT_ACCESSIBLE` | User not in docker group | `sudo usermod -aG docker $USER` |
| `POSTGRES_NOT_READY` | Container stopped | `docker compose up -d postgres` |
| `DISK_SPACE_LOW` | Less than 1GB free | `docker system prune -a` |
| `BACKUP_DIR_NOT_WRITABLE` | Permission issue | `sudo chown -R $USER:$USER /local-files/backups` |

---

## SSH Key Setup

### Generate Key on VPS

```bash
# On VPS (as the deploy user)
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github_actions -N ""

# Add to authorized_keys
cat ~/.ssh/github_actions.pub >> ~/.ssh/authorized_keys

# Display private key (copy this to GitHub secret)
cat ~/.ssh/github_actions
```

### Add to GitHub

1. Go to repo **Settings** > **Secrets and variables** > **Actions**
2. Click **New repository secret**
3. Name: `VPS_SSH_KEY`
4. Value: Paste the entire private key (including `-----BEGIN...` lines)

### Test Connection

```bash
# From any machine with the private key
ssh -i /path/to/key deploy@72.60.190.192 "echo 'SSH OK'"
```

---

## VPS User Setup (Non-root)

If using a non-root user (`deploy`), ensure:

```bash
# 1. Create user
sudo adduser deploy

# 2. Add to docker group
sudo usermod -aG docker deploy

# 3. Create backup directory with proper ownership
sudo mkdir -p /local-files/backups/resto-bot
sudo chown -R deploy:deploy /local-files/backups

# 4. Verify
su - deploy
docker ps  # Should work without sudo
touch /local-files/backups/resto-bot/test && rm /local-files/backups/resto-bot/test  # Should work
```

---

## Validation Checklist

### After Deployment

- [ ] Set `HEALTH_URL` variable pointing to API gateway
- [ ] Configure `VPS_SSH_KEY` secret
- [ ] VPS user is in docker group
- [ ] Backup directory is writable
- [ ] Run health monitor manually: `gh workflow run "Health Monitor"`
- [ ] Run backup manually: `gh workflow run "Scheduled Backup" -f backup_type=daily`

### VPS Health Commands

```bash
# Check containers
docker compose -f /docker/n8n/docker-compose.hostinger.prod.yml ps

# Check postgres
docker compose -f /docker/n8n/docker-compose.hostinger.prod.yml exec -T postgres pg_isready -U n8n -d n8n

# Check disk
df -h /

# Check local health
curl -s http://localhost:8080/healthz

# List backups
ls -la /local-files/backups/resto-bot/

# Test restore (dry run)
gunzip -c /local-files/backups/resto-bot/daily-*-db.dump.gz | pg_restore -l | head -20
```

---

## Rollback Procedures

### Health Monitor

The health monitor is read-only and doesn't modify anything. No rollback needed.

### Backup Workflow

Backups are additive. To rollback a bad backup:

```bash
# On VPS
cd /local-files/backups/resto-bot
rm -f bad-backup-*  # Remove corrupted files
```

### Restore from Backup

```bash
# On VPS
cd /docker/n8n
BACKUP_FILE="/local-files/backups/resto-bot/daily-YYYYMMDD-HHMMSS-db.dump.gz"

# Stop n8n (keep postgres running)
docker compose -f docker-compose.hostinger.prod.yml stop n8n-main n8n-worker

# Restore
gunzip -c "$BACKUP_FILE" | docker compose -f docker-compose.hostinger.prod.yml exec -T postgres \
  pg_restore -U n8n -d n8n --clean --if-exists --no-owner

# Restart
docker compose -f docker-compose.hostinger.prod.yml up -d
```

---

## Alerts Configuration

### Slack Webhook

1. Create incoming webhook in Slack: Apps > Incoming Webhooks
2. Add `ALERT_WEBHOOK_URL` secret with the webhook URL

### Discord Webhook

1. Server Settings > Integrations > Webhooks > New Webhook
2. Append `/slack` to the URL: `https://discord.com/api/webhooks/xxx/yyy/slack`
3. Add as `ALERT_WEBHOOK_URL`

---

## Common Issues

### Workflow shows "All jobs failed"

1. Check the workflow run logs in GitHub Actions
2. Look for the specific step that failed
3. Most common causes:
   - SSH key not configured or invalid
   - VPS unreachable (firewall, down)
   - Docker not accessible (user permissions)
   - Health URL pointing to protected endpoint

### Backup file is empty or corrupted

1. Check postgres is healthy: `docker compose exec postgres pg_isready`
2. Check disk space: `df -h /`
3. Run manual pg_dump to see errors: `docker compose exec postgres pg_dump -U n8n -d n8n | head`

### SSH connection refused

1. Verify VPS firewall allows SSH (port 22)
2. Check SSH key format (should be `-----BEGIN OPENSSH PRIVATE KEY-----`)
3. Verify user exists and key is in `~/.ssh/authorized_keys`
