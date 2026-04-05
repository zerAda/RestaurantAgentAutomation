---
phase: 01-data-protection
plan: 01
subsystem: backup-infrastructure
tags: [backup, s3, gpg, restore, disaster-recovery]
dependency_graph:
  requires: []
  provides: [off-site-backup, restore-drill]
  affects: [scheduled-backup-workflow, backup-documentation]
tech_stack:
  added: [awscli, gpg-symmetric-encryption]
  patterns: [encrypt-before-upload, trap-cleanup, fail-fast-secrets-check]
key_files:
  created:
    - scripts/restore_drill.sh
    - PATCHLOG.md
  modified:
    - .github/workflows/scheduled-backup.yml
    - docs/BACKUP_RESTORE.md
    - docs/RUNBOOK.md
decisions:
  - "upload-offsite job fails the workflow (not continue-on-error) if S3 secrets are missing — silently skipping off-site backup is unacceptable for disaster recovery"
  - "GPG symmetric AES-256 encryption happens on the GitHub Actions runner before upload, keeping raw dumps off S3"
  - "restore_drill.sh uses trap cleanup EXIT so temp pg_drill_$$ container is always removed even on script failure"
  - "BACKUP_NAME passed via needs.backup.outputs.backup_name so upload-offsite always uploads the exact backup that was verified"
metrics:
  duration: ~25min
  completed: 2026-03-21
  tasks_completed: 2
  tasks_skipped: 1
  files_created: 2
  files_modified: 3
---

# Phase 01 Plan 01: Off-Site Backup with S3 Upload and GPG Encryption — Summary

**One-liner:** Daily PostgreSQL dumps are now GPG AES-256 encrypted and uploaded to S3-compatible storage via GitHub Actions; `restore_drill.sh` automates pull-decrypt-restore-verify against a throwaway Postgres container.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add S3 upload step to scheduled-backup.yml | (see final commit) | `.github/workflows/scheduled-backup.yml` |
| 2 | Write restore_drill.sh + update docs | (see final commit) | `scripts/restore_drill.sh`, `docs/BACKUP_RESTORE.md`, `docs/RUNBOOK.md`, `PATCHLOG.md` |

## Tasks Skipped

| Task | Name | Reason |
|------|------|--------|
| 3 | Human verification checkpoint | Skipped per execution instructions — requires S3 credentials and a live workflow run |

---

## What Was Built

### `.github/workflows/scheduled-backup.yml` — upload-offsite job

New `upload-offsite` job added after the existing `backup` job:
- `needs: [backup]` with `if: needs.backup.outputs.backup_success == 'true'`
- Fails the workflow (not `continue-on-error`) if `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, or `BACKUP_GPG_PASSPHRASE` secrets are missing
- Downloads `${BACKUP_NAME}-db.dump.gz` from VPS via scp
- Verifies gzip integrity on the runner
- GPG AES-256 symmetric encryption: `echo "$BACKUP_GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 ...`
- Uploads `.gpg` file to `s3://${S3_BACKUP_BUCKET}/postgres/` via awscli with `--endpoint-url` and `--region`
- Always cleans up temp files (`if: always()`)
- `summary` job updated: `needs` now includes `upload-offsite`; Off-site Upload row added to summary table

### `scripts/restore_drill.sh`

Fully automated restore drill script:
- `#!/usr/bin/env bash` + `set -euo pipefail`
- Accepts `BACKUP_NAME` as `$1` or env var
- Fails fast if any of 6 required env vars are missing
- `trap cleanup EXIT` ensures `pg_drill_$$` container and `/tmp/` files are always removed
- Downloads encrypted backup from S3
- Decrypts with GPG passphrase
- Decompresses gzip
- Spins up `postgres:15-alpine` container, polls `pg_isready` up to 30s
- Restores with `pg_restore --clean --no-owner --no-acl -Fc`
- Verifies `SELECT COUNT(*) FROM workflow_entity > 0`
- Prints `[DRILL PASS]` or `[DRILL FAIL]` as final line

### `docs/BACKUP_RESTORE.md`

Complete rewrite (110+ lines) covering:
- Architecture diagram: VPS -> GitHub Actions -> S3
- Backup inventory table (what is backed up, format, location)
- Schedule and retention table
- Off-site restore procedure with exact commands
- Manual emergency restore (no GitHub Actions)
- Verification SQL queries
- GitHub Actions secrets configuration table
- Redis backup procedure

### `docs/RUNBOOK.md`

Added "Restore from Off-site Backup" section (section 5) covering:
- When to use (VPS disk failure, ENOSPC, accidental deletion, provider outage)
- Prerequisites
- Quick command with `restore_drill.sh`
- After-restore checklist
- Updated Go-Live checklist with S3 backup and drill verification items

### `PATCHLOG.md`

Created new file at repo root with Phase 01 entry documenting what/why/risk/rollback.

---

## Deviations from Plan

None — plan executed exactly as written (Tasks 1 and 2 completed in full; Task 3 skipped per user instructions).

---

## User Action Required

Before the `upload-offsite` job will succeed, configure in **GitHub repo > Settings > Secrets and variables > Actions**:

**Secrets (encrypted):**
- `S3_ACCESS_KEY_ID` — S3/R2 access key ID
- `S3_SECRET_ACCESS_KEY` — S3/R2 secret key
- `BACKUP_GPG_PASSPHRASE` — GPG symmetric passphrase for encryption

**Variables (plaintext):**
- `S3_BACKUP_BUCKET` — bucket name (e.g. `resto-bot-backups`)
- `S3_BACKUP_ENDPOINT` — S3 endpoint URL (e.g. `https://s3.amazonaws.com` or R2 URL)
- `S3_BACKUP_REGION` — region (e.g. `us-east-1` or `auto` for R2)

Once configured, trigger the `Scheduled Backup` workflow manually (Actions > Scheduled Backup > Run workflow > `backup_type: daily`) and confirm all jobs green including `upload-offsite`.

---

## Self-Check

Files created/modified:
- `.github/workflows/scheduled-backup.yml` — upload-offsite job present, no continue-on-error, aws s3 cp present
- `scripts/restore_drill.sh` — shebang correct, set -euo pipefail, trap cleanup EXIT, [DRILL PASS] marker
- `docs/BACKUP_RESTORE.md` — 110+ lines, full procedure
- `docs/RUNBOOK.md` — Restore from Off-site Backup section present
- `PATCHLOG.md` — Phase 01 entry at top

## Self-Check: PASSED
