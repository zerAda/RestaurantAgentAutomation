# CI/CD Documentation - Resto Bot

## Architecture Overview

```
PR opened/updated
    |
    v
[CI Pipeline] ─── lint ─── unit-tests ─── integration-tests ─── docker-build ─── security-scan
    |                                                                                  |
    v                                                                                  v
  merge to main                                                                   ci-summary
    |
    v
[CD Pipeline] ─── preflight ─── security-gate ─── backup ─── deploy ─── cleanup ─── post-deploy
                                                      |           |
                                                  (pg_dump)   (release dir)
                                                              (migrations)
                                                              (symlink cutover)
                                                              (health check)
                                                              (smoke tests)
                                                              (auto-rollback on failure)
```

## Workflows

### GitHub Actions (`.github/workflows/`)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | PR + push to main/develop | Lint, test, build, security scan |
| `cd-deploy.yml` | CI success on main + manual | Deploy to VPS with backup/migrate/rollback |
| `production-build.yml` | push/PR to main | Docker build verification |
| `security-scan.yml` | push/PR to main + weekly | Gitleaks, Trivy, SBOM |
| `health-monitor.yml` | every 6 hours + manual | HTTP + SSH health checks |
| `scheduled-backup.yml` | daily 3am + weekly 4am UTC | pg_dump with rotation |
| `rollback.yml` | manual only | Rollback to previous release |

### GitLab CI (`.gitlab-ci.yml`)

| Stage | Job | Purpose |
|-------|-----|---------|
| validate | `lint-json` | Validate all workflow JSON files |
| validate | `lint-bash` | Syntax-check all shell scripts |
| validate | `lint-nginx` | Validate nginx config (allow_failure) |
| test | `unit-tests` | Contract validation + L10N tests |
| test | `integration-tests` | Bootstrap + 26 migrations + schema verification |
| build | `docker-build` | Compose file validation with all env vars |
| security | `security-scan` | .env check, secrets grep, nginx headers |
| deploy | `deploy-staging` / `deploy-production` | Manual stubs (use GitHub Actions for production) |

## Deployment Model

### Release Directory Structure

```
/opt/resto/
├── current -> releases/20260206-143022-abc1234/  (symlink)
├── releases/
│   ├── 20260206-143022-abc1234/  (current)
│   ├── 20260205-120000-def5678/  (previous)
│   ├── 20260204-093000-ghi9012/
│   └── ... (keeps last 5)
├── shared/
│   ├── .env                      (persistent across releases)
│   └── secrets/
│       ├── postgres_password
│       ├── n8n_encryption_key
│       └── traefik_usersfile
└── backups/
    ├── deploy-20260206-...-n8n.dump
    ├── deploy-20260206-...-strapi.dump
    ├── daily-20260206-...-db.dump.gz
    └── full-20260203-...-db.dump.gz
```

### Deploy Steps

1. **Preflight**: validate variables, check SSH, detect first-deploy vs update, verify disk space
2. **Security Gate**: Gitleaks scan, verify no `.env` committed
3. **Backup**: `pg_dump -Fc` of both `n8n` and `strapi` databases + config tarball
4. **Deploy**:
   - Create new release directory under `/opt/resto/releases/<deploy-id>/`
   - `rsync` code from CI runner to release directory
   - Symlink shared `.env` and `secrets/` into release
   - Copy `docker-compose.hostinger.prod.yml` to `docker-compose.yml`
   - Pull/build images
   - Run `db-migrate` service (gated — failure stops deploy)
   - `docker compose up -d --remove-orphans`
   - Update symlink: `/opt/resto/current -> /opt/resto/releases/<deploy-id>/`
   - Health check (15 retries, 10s interval)
   - Smoke tests (6 checks, must pass 4+)
5. **Cleanup**: prune old releases (keep 5), prune Docker images, rotate backups
6. **Post-deploy**: record deployment, auto-rollback if failed, notify

## Database Operations

### How Migrations Work

Migrations live in `db/migrations/` as idempotent SQL files (sorted by filename).

The `db-migrate` service in `docker-compose.hostinger.prod.yml`:
1. Waits for PostgreSQL to be ready
2. Creates `schema_migrations` tracking table
3. Checks each `.sql` file against already-applied list
4. Applies pending migrations with `ON_ERROR_STOP=1`
5. Records each successful migration in `schema_migrations`

**Migration table:** `schema_migrations` (used consistently in compose and CI)

### How Backups Work

**Pre-deploy backup** (automatic):
- `pg_dump -Fc` of `n8n` database
- `pg_dump -Fc` of `strapi` database (if exists)
- Config tarball (`.env` + `secrets/`)
- Stored in `/opt/resto/backups/`

**Scheduled backup** (daily at 3am UTC):
- `pg_dump -Fc` with gzip compression
- Integrity verification (`gunzip -t`)
- Rotation: 7 daily, 4 weekly

**Manual backup**:
```bash
cd /opt/resto/current
./scripts/backup_postgres.sh
```

### How to Restore a Database

```bash
# On the VPS:
cd /opt/resto/current

# List available backups
ls -lht /opt/resto/backups/

# Restore from a specific backup (stops app, restores, restarts)
CONFIRM_RESTORE=YES ./scripts/restore_postgres.sh --clean --if-exists \
  /opt/resto/backups/deploy-20260206-143022-abc1234-n8n.dump
```

## Rollback

### Automatic Rollback
If health checks or smoke tests fail during deployment, the CD pipeline automatically:
1. Finds the previous release directory
2. Switches the `/opt/resto/current` symlink back
3. Runs `docker compose up -d --remove-orphans`
4. Verifies PostgreSQL is ready

### Manual Rollback (via GitHub Actions)
1. Go to **Actions** > **Rollback Deployment**
2. Click **Run workflow**
3. Select rollback type: `config` (just .env/secrets) or `full` (config + database)
4. Type `ROLLBACK` to confirm
5. Enter reason

### Manual Rollback (SSH)
```bash
ssh deploy@<VPS_HOST>

# List releases
ls -lt /opt/resto/releases/

# Switch to previous release
ln -sfn /opt/resto/releases/<previous-id> /opt/resto/current
cd /opt/resto/current
docker compose up -d --remove-orphans

# Verify
docker compose ps
docker compose exec -T postgres pg_isready -U n8n
```

## VPS Setup Requirements

### Repository Variables (Settings > Variables > Actions)

| Variable | Example | Required |
|----------|---------|----------|
| `VPS_HOST` | `72.60.190.192` | Yes |
| `VPS_USER` | `deploy` | No (default: `deploy`) |
| `PROJECT_DIR` | `/opt/resto` | No (default: `/opt/resto`) |
| `BACKUP_DIR` | `/opt/resto/backups` | No (default: `/opt/resto/backups`) |
| `LOG_DIR` | `/var/log/resto-bot` | No (default) |
| `HEALTH_URL` | `https://api.example.com/healthz` | Yes |
| `DOMAIN` | `srv1258231.hstgr.cloud` | Yes |

### Repository Secrets (Settings > Secrets > Actions)

| Secret | Purpose |
|--------|---------|
| `VPS_SSH_KEY` | ed25519 private key for deploy user |
| `ALERT_WEBHOOK_URL` | Slack/Discord webhook for notifications |

### Deploy User Setup (on VPS)

```bash
# Create deploy user (do NOT use root)
useradd -m -s /bin/bash deploy
usermod -aG docker deploy

# Generate SSH key
su - deploy
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github_actions
cat ~/.ssh/github_actions.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Copy private key to GitHub Secrets (VPS_SSH_KEY)
cat ~/.ssh/github_actions

# Create project directories
sudo mkdir -p /opt/resto/{releases,shared/secrets,backups}
sudo chown -R deploy:deploy /opt/resto
sudo mkdir -p /var/log/resto-bot
sudo chown deploy:deploy /var/log/resto-bot
```

### First Deploy

1. Copy `.env` to `/opt/resto/shared/.env`
2. Copy secrets to `/opt/resto/shared/secrets/`
3. Run CD pipeline with **Force full deployment** checked

## Troubleshooting

### Deploy fails at "Health check"
```bash
ssh deploy@VPS
cd /opt/resto/current
docker compose ps          # Check which services are running
docker compose logs --tail=50 n8n-main  # Check n8n logs
docker compose logs --tail=50 postgres  # Check DB logs
```

### Deploy fails at "Run migrations"
```bash
ssh deploy@VPS
cd /opt/resto/current
docker compose logs db-migrate --tail=100
# Check which migrations are pending:
docker compose exec postgres psql -U n8n -d n8n -c "SELECT * FROM schema_migrations ORDER BY id;"
```

### Smoke tests fail
- Check that `HEALTH_URL` variable points to the **public API gateway** (not the protected console)
- Verify DNS resolves: `nslookup api.<domain>`
- Check Traefik: `docker compose logs traefik --tail=20`

### Database backup fails
```bash
# Check postgres is running
docker compose exec postgres pg_isready -U n8n
# Check disk space
df -h /opt/resto/backups/
# Manual backup
docker compose exec -T postgres pg_dump -U n8n -d n8n -Fc > /opt/resto/backups/manual-$(date +%Y%m%d).dump
```
