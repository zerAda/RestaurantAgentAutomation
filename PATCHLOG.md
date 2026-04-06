# PATCHLOG — Resto Bot

This file tracks significant infrastructure and platform patches applied to the project.
Each entry documents what changed, why, the risk level, and how to roll back.

---

## 2026-04-06 — CI/CD Pipeline Recovery (5 Critical Fixes)

- **What**: Six commits (`358ea78` → `f344190`) resolving a cascade of CI/CD failures that kept production at HTTP 503:
  1. **Duplicate CD trigger** — `ralphe-cd-deploy.yml` shared the same name and `workflow_run:` trigger as `cd-deploy.yml`; both fired simultaneously and fought for the `deploy-production` concurrency slot, permanently blocking production. Fixed by renaming and removing its auto-trigger.
  2. **nginx health check port mismatch** — CI smoke-routing service was mapped `8080:8080` but nginx listens on port 80 inside the container; health check was hitting nothing. Fixed: `8080:80` + `curl localhost/`.
  3. **Backup picking staging postgres** — When staging and production ran concurrently, `docker ps -qf "ancestor=postgres"` returned the staging container first; pg_dump of empty staging DB → empty dump → backup failure. Fixed by filtering on compose project label.
  4. **Secret bind-mounts missing on re-deploys** — `docker-compose.ghcr.yml` bind-mounts `secrets/traefik_usersfile`, `secrets/postgres_password`, `secrets/n8n_encryption_key`. These were only created on `IS_FIRST=true`; on any re-deploy Docker aborted with "bind source path does not exist". Fixed: create on every deploy with `if [ ! -f ]` guards.
  5. **External Docker volumes missing on re-deploys** — All 6 named volumes (`traefik_data`, `n8n_data`, `postgres_data`, `redis_data`, `cms_uploads`, `ollama_data`) are `external: true` and must pre-exist before `docker compose up`. Previously created only on first deploy. Fixed: `docker volume create ... 2>/dev/null || true` on every deploy.
  6. **`/var/log/resto-bot` permission denied** — `deploy` user on hardened VPS cannot write to `/var/log/`; `mkdir -p /var/log/resto-bot` was failing silently via `set -euo pipefail`, aborting the entire deploy in ~21 seconds before any Docker work started. Fixed with fallback to `$PROJECT_DIR/logs`. ERR trap also added to print exact failure line in Step Summary.
- **Why**: Production VPS was serving HTTP 503. Every automatic CD run was failing before containers were ever updated. All 6 issues formed a blocking cascade.
- **Risk**: Low — all changes are additive or fallback-guarded. Secret and volume creation is idempotent (`2>/dev/null || true` / `if [ ! -f ]`). Backup failure no longer blocks deploy (warning emitted instead).
- **Rollback**: `git revert` of commits `358ea78..f344190`. No VPS-side state changes required.
- **Files changed**: `.github/workflows/ralphe-cd-deploy.yml`, `.github/workflows/ci.yml`, `.github/workflows/cd-deploy.yml`, `scripts/ops/backup.sh`, `scripts/ops/deploy_to_node.sh`

---

## 2026-03-21 — Phase 01: Off-Site Backup Implementation

- **What**: Added `upload-offsite` job to `.github/workflows/scheduled-backup.yml`; GPG AES-256 encryption before upload; `scripts/restore_drill.sh` automated restore verification script; updated `docs/BACKUP_RESTORE.md` and `docs/RUNBOOK.md`
- **Why**: Local-only backup is insufficient — if the VPS 119 GB disk fails or hits ENOSPC (a documented recurring risk), both the live database and the only backup copy are lost together. Total data loss would be unrecoverable. Off-site S3 backup closes this gap.
- **Risk**: Low — additive change only. The existing `backup` job is untouched. The new `upload-offsite` job is independent and only runs after a successful backup. `restore_drill.sh` is non-destructive (uses a throwaway container).
- **Rollback**: Remove the `upload-offsite` job from `.github/workflows/scheduled-backup.yml` and revert `summary` job `needs` array. No VPS-side changes required. `git revert` of the Phase 01 commit is sufficient.
- **User action required**: Configure GitHub Actions secrets `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `BACKUP_GPG_PASSPHRASE` and variables `S3_BACKUP_BUCKET`, `S3_BACKUP_ENDPOINT`, `S3_BACKUP_REGION` before the upload-offsite job will succeed.
