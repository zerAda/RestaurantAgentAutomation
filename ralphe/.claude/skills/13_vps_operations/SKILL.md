---
name: vps_operations
description: VPS deployment, directory layout, env sync, backup execution, SSH access, and operational procedures.
when_to_use:
  - Deploying to production VPS
  - Setting up new VPS
  - Running backups or restores
  - Debugging VPS issues
  - Environment sync checks
---

# VPS Operations

## VPS details

- Provider: Hostinger
- OS: Ubuntu 24.04
- Domain: `srv1258231.hstgr.cloud` (or custom domain)
- Users: `root` (admin), `deploy` (deployment, docker group)
- SSH: `deploy@<vps-ip>` with ed25519 key

## Directory layout

```
/opt/resto/
  releases/          # Timestamped release directories
  staging/           # Pre-deploy staging area
  shared/
    .env             # Production environment file
    secrets/         # Additional secret files
    cosign/          # Cosign keypair (cosign.key, cosign.pub)
  backups/           # DB and Redis backup files
  docker-compose.hostinger.prod.yml  # Production compose (symlinked or copied)

/var/log/resto-bot/  # Application logs
```

## Deployment flow (cd-deploy.yml)

1. Setup SSH via `.github/actions/setup-ssh/` composite action
2. SSH to VPS as `deploy` user
3. Pull latest Docker images from GHCR
4. Run `docker compose -f docker-compose.hostinger.prod.yml up -d`
5. Run health check via `.github/actions/health-check/`
6. Notify via `.github/actions/notify/` (Slack + Discord)

## Environment management

- Template: `config/.env.example` (614 lines, 27 sections)
- VPS file: `/opt/resto/shared/.env`
- Sync check: `.github/workflows/env-sync.yml`
- Manual sync check: `scripts/env_sync_check.sh`
- NEVER commit `.env` to git (gitignored)

## Backup operations

```bash
# SSH to VPS
ssh deploy@<vps-ip>

# DB backup
/opt/resto/scripts/backup_postgres.sh

# Redis backup
/opt/resto/scripts/backup_redis.sh

# Verify backup
ls -la /opt/resto/backups/

# Restore (requires CONFIRM_RESTORE=yes)
CONFIRM_RESTORE=yes /opt/resto/scripts/restore_postgres.sh /opt/resto/backups/<file>.sql.gz
```

## GitHub Actions configuration

### Secrets

| Secret | Purpose |
|--------|---------|
| `VPS_SSH_KEY` | ed25519 private key for `deploy` user |
| `COSIGN_PRIVATE_KEY` | Image signing key |
| `COSIGN_PASSWORD` | Cosign key decryption password |

### Variables

| Variable | Value |
|----------|-------|
| `VPS_HOST` | VPS IP address |
| `VPS_USER` | `deploy` |
| `PROJECT_DIR` | `/opt/resto` |
| `BACKUP_DIR` | `/opt/resto/backups` |
| `LOG_DIR` | `/var/log/resto-bot` |
| `DOMAIN` | `srv1258231.hstgr.cloud` |
| `HEALTH_URL` | `https://api.<domain>/v1/health` |

## Troubleshooting

```bash
# Check all containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check specific service logs
docker logs --tail 100 n8n-main
docker logs --tail 100 gateway
docker logs --tail 100 traefik

# Check disk space
df -h /opt/resto /var/lib/docker

# Check Redis queue depth
docker exec redis redis-cli -a <password> LLEN bull:default:wait

# Restart a service
docker compose -f docker-compose.hostinger.prod.yml restart <service>
```

## Deliverables

- VPS state verification (all services running, health check passing)
- Backup verification (recent backup exists, size > 0)
- Env sync check passes
- SSH access verified
