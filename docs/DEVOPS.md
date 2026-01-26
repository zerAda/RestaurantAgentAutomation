# DevSecOps Guide - Resto Bot

## Overview

This document describes the CI/CD pipeline and DevSecOps practices for Resto Bot.

## Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              GitHub Repository                               │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            CI Pipeline (ci.yml)                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │     Lint     │  │   Security   │  │    Python    │  │    Build     │    │
│  │   & Syntax   │  │    Gates     │  │    Tests     │  │   Package    │    │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘    │
│         │                 │                 │                 │             │
│         └─────────────────┴─────────────────┴─────────────────┘             │
│                                      │                                      │
└──────────────────────────────────────┼──────────────────────────────────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
┌─────────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
│   Security Scan         │ │   CD Deploy         │ │   Scheduled Backup  │
│   (security-scan.yml)   │ │   (cd-deploy.yml)   │ │   (scheduled-       │
│   - Secret detection    │ │   - Staging/Prod    │ │    backup.yml)      │
│   - Container scan      │ │   - Auto-rollback   │ │   - Daily/Weekly    │
│   - SAST                │ │   - Notifications   │ │   - DB + Config     │
└─────────────────────────┘ └─────────────────────┘ └─────────────────────┘
                                       │
                                       ▼
                            ┌─────────────────────┐
                            │   Health Monitor    │
                            │   (Every 15 min)    │
                            │   - Service health  │
                            │   - Disk space      │
                            │   - Queue depth     │
                            └─────────────────────┘
```

## Workflows

### 1. CI Pipeline (`ci.yml`)

**Trigger:** Push to main/master, Pull Requests

**Jobs:**
| Job | Purpose | Runs |
|-----|---------|------|
| `lint` | Bash, YAML, JSON validation | Parallel |
| `security-gates` | Secret scan, workflow security checks | Parallel |
| `python-tests` | Schema, L10N, template, Darija tests | Parallel |
| `build` | Create deployment package | After all pass |
| `ci-summary` | Generate summary report | Always |

### 2. Security Scan (`security-scan.yml`)

**Trigger:** Push, PR, Weekly (Sundays)

**Jobs:**
| Job | Purpose |
|-----|---------|
| `secret-scan` | Gitleaks + custom patterns |
| `container-scan` | Trivy scan on all images |
| `config-scan` | Docker Compose, Nginx, env security |
| `dependency-scan` | Python dependencies, n8n workflow nodes |
| `sbom` | Generate Software Bill of Materials |

### 3. CD Deploy (`cd-deploy.yml`)

**Trigger:** After CI success, Manual dispatch

**Features:**
- Environment selection (staging/production)
- Concurrency lock (one deploy at a time)
- Pre-deployment validation
- Database backup before deploy
- Health checks with retry
- Smoke tests
- Auto-rollback on failure
- Notifications (Slack/webhook)

### 4. Rollback (`rollback.yml`)

**Trigger:** Manual only (requires confirmation)

**Types:**
| Type | Restores |
|------|----------|
| `config` | .env, secrets/ |
| `full` | Config + Database |
| `code_only` | Git checkout previous commit |

### 5. Scheduled Backup (`scheduled-backup.yml`)

**Schedule:**
- Daily: 3:00 AM UTC
- Weekly (full): Sunday 4:00 AM UTC

**Retention:**
- Daily backups: 7 days
- Weekly backups: 4 weeks

### 6. Health Monitor (`health-monitor.yml`)

**Schedule:** Every 15 minutes

**Checks:**
- n8n health endpoint
- PostgreSQL connectivity
- Redis ping
- Container count
- Disk usage
- Queue depth

## Security Practices

### Secret Management

1. **Never commit secrets** - Use `.env` (gitignored) and `secrets/` volume
2. **Secret scanning** - Gitleaks runs on every push
3. **Environment variables** - All secrets via env vars, not hardcoded
4. **Token rotation** - Regularly rotate API tokens and passwords

### Security Gates in CI

```yaml
# Required security checks before merge:
- ALLOW_QUERY_TOKEN gate in inbound workflows
- scopeOk enforcement in token validation
- Contract validation gate
- No CHANGE_ME placeholders
- Security flags in .env.example
```

### Container Security

- All images scanned with Trivy
- No privileged containers
- Minimal base images (alpine where possible)
- Regular image updates via Dependabot

## Deployment Process

### Standard Deployment

```bash
# 1. Push to main triggers CI
git push origin main

# 2. CI validates and builds
# 3. CD deploys automatically on CI success
# 4. Health checks verify deployment
# 5. Notification sent on success/failure
```

### Manual Deployment

```bash
# Via GitHub Actions UI:
# 1. Go to Actions > CD - Deploy to VPS
# 2. Click "Run workflow"
# 3. Select environment (staging/production)
# 4. Optionally skip backup or force deploy
```

### Rollback

```bash
# Via GitHub Actions UI:
# 1. Go to Actions > Rollback Deployment
# 2. Click "Run workflow"
# 3. Select rollback type
# 4. Provide backup name (or leave empty for latest)
# 5. Type "ROLLBACK" to confirm
# 6. Provide reason for audit
```

## Monitoring & Alerting

### Alerts

Configure `ALERT_WEBHOOK_URL` secret for notifications:
- Deployment success/failure
- Rollback events
- Health check failures
- Backup failures

### Log Locations

| Log | Location |
|-----|----------|
| Deployment log | `/var/log/resto-bot/deployments.log` |
| Rollback log | `/var/log/resto-bot/rollbacks.log` |
| Container logs | `docker compose logs <service>` |

## Backup & Recovery

### Backup Contents

| Backup Type | Contents |
|-------------|----------|
| `-db.sql.gz` | PostgreSQL dump |
| `-config.tar.gz` | .env, secrets/ |
| `-redis.rdb` | Redis snapshot (full only) |
| `-sha.txt` | Git commit SHA |
| `-images.txt` | Docker image versions |

### Manual Restore

```bash
# On VPS:
cd /opt/resto-bot

# Restore config
tar -xzvf /opt/resto-bot-backups/deploy-XXXXX-config.tar.gz

# Restore database
docker compose -f docker-compose.hostinger.prod.yml up -d postgres
gunzip -c /opt/resto-bot-backups/deploy-XXXXX-db.sql.gz | \
  docker compose exec -T postgres psql -U n8n -d n8n

# Restart stack
docker compose -f docker-compose.hostinger.prod.yml up -d
```

## GitHub Repository Settings

### Recommended Settings

1. **Branch Protection (main):**
   - Require PR reviews
   - Require status checks (CI)
   - Require branches to be up to date
   - Include administrators

2. **Secrets:**
   - `ALERT_WEBHOOK_URL` - Slack/webhook URL for notifications

3. **Variables:**
   - `DOMAIN_NAME` - Production domain

4. **Environments:**
   - `production` - With deployment protection rules
   - `staging` - For testing deployments

## Quick Reference

### Commands

```bash
# Run CI tests locally
./scripts/integrity_gate.sh
python scripts/validate_contracts.py
./scripts/smoke.sh

# View deployment logs
tail -f /var/log/resto-bot/deployments.log

# Check service health
docker compose -f docker-compose.hostinger.prod.yml ps
curl http://localhost:5678/healthz

# Manual backup
docker compose exec postgres pg_dump -U n8n -d n8n | gzip > backup.sql.gz
```

### Troubleshooting

| Issue | Solution |
|-------|----------|
| Deploy stuck | Check concurrency lock, cancel if needed |
| Health check fails | Check container logs, verify ports |
| Rollback fails | Use pre-rollback backup manually |
| Secret scan fails | Check `.gitleaks.toml` allowlist |
