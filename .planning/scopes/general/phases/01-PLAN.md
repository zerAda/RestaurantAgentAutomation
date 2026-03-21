---
phase: 01-data-protection
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - project/.github/workflows/scheduled-backup.yml
  - project/scripts/backup_postgres.sh
  - project/scripts/restore_drill.sh
  - project/docs/BACKUP_RESTORE.md
  - project/RUNBOOK.md
  - project/PATCHLOG.md
autonomous: false
requirements: [BAK-01, BAK-02, BAK-03]
user_setup:
  - service: s3-compatible-storage
    why: "Off-site backup destination for PostgreSQL dumps"
    env_vars:
      - name: S3_BACKUP_BUCKET
        source: "Your S3/R2/B2 bucket name (e.g. resto-bot-backups)"
      - name: S3_BACKUP_ENDPOINT
        source: "S3 endpoint URL (e.g. https://s3.amazonaws.com or Cloudflare R2 endpoint)"
      - name: S3_BACKUP_REGION
        source: "AWS region or 'auto' for R2"
      - name: AWS_ACCESS_KEY_ID
        source: "S3/R2 access key ID — add to GitHub Actions secrets as S3_ACCESS_KEY_ID"
      - name: AWS_SECRET_ACCESS_KEY
        source: "S3/R2 secret key — add to GitHub Actions secrets as S3_SECRET_ACCESS_KEY"
      - name: BACKUP_GPG_PASSPHRASE
        source: "Passphrase for GPG encryption of backup files — add to GitHub Actions secrets as BACKUP_GPG_PASSPHRASE"
    dashboard_config:
      - task: "Create S3 bucket (or R2 bucket) with versioning disabled and private ACL"
        location: "AWS Console / Cloudflare R2 Dashboard"
      - task: "Create IAM user (or R2 API token) with s3:PutObject + s3:GetObject permissions on that bucket only"
        location: "AWS IAM Console / Cloudflare R2 API Tokens"
      - task: "Add S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY, BACKUP_GPG_PASSPHRASE, S3_BACKUP_BUCKET, S3_BACKUP_ENDPOINT, S3_BACKUP_REGION as GitHub Actions secrets"
        location: "GitHub repo > Settings > Secrets and variables > Actions"

must_haves:
  truths:
    - "A daily backup is uploaded to off-site S3-compatible storage automatically"
    - "If the S3 upload fails, the GitHub Actions workflow fails (not silently skipped)"
    - "Each backup is GPG-encrypted before upload"
    - "A restore drill script can pull the latest off-site backup, decrypt it, and restore to a test container"
    - "BACKUP_RESTORE.md documents exact recovery commands"
  artifacts:
    - path: "project/.github/workflows/scheduled-backup.yml"
      provides: "Backup workflow with S3 upload step"
      contains: "aws s3 cp"
    - path: "project/scripts/restore_drill.sh"
      provides: "Off-site restore verification script"
      exports: []
    - path: "project/docs/BACKUP_RESTORE.md"
      provides: "Step-by-step recovery procedure"
      min_lines: 60
  key_links:
    - from: "scheduled-backup.yml backup job"
      to: "S3_BACKUP_BUCKET"
      via: "aws s3 cp after gunzip integrity check"
      pattern: "aws s3 cp.*S3_BACKUP_BUCKET"
    - from: "restore_drill.sh"
      to: "S3_BACKUP_BUCKET"
      via: "aws s3 cp download + gpg decrypt + pg_restore"
      pattern: "aws s3 cp.*download"
---

<objective>
Implement automated off-site PostgreSQL backup with encryption and a tested restore drill.

Purpose: The current backup only writes to `/opt/resto/backups/` on the VPS local disk. If the 119 GB VPS disk fails or hits ENOSPC (a documented recurring risk), both the live database and the only backup are lost together — unrecoverable. This phase closes that gap.

Output:
- `scheduled-backup.yml` extended with an S3 upload step (encrypted, blocking on failure)
- `scripts/restore_drill.sh` — pulls latest backup from S3, decrypts, restores to scratch container, verifies row counts
- `docs/BACKUP_RESTORE.md` — full recovery procedure documentation
- `RUNBOOK.md` "Restore from off-site backup" section
- `PATCHLOG.md` entry
</objective>

<execution_context>
@C:/Users/mon pc/Desktop/ralphé_final_patch/.claude/get-shit-done/workflows/execute-plan.md
@C:/Users/mon pc/Desktop/ralphé_final_patch/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@C:/Users/mon pc/Desktop/ralphé_final_patch/.planning/scopes/general/ROADMAP.md
@C:/Users/mon pc/Desktop/ralphé_final_patch/.planning/scopes/general/codebase/ARCHITECTURE.md
@C:/Users/mon pc/Desktop/ralphé_final_patch/.planning/scopes/general/codebase/CONCERNS.md

<!-- Key files to read before editing -->
@C:/Users/mon pc/Desktop/ralphé_final_patch/project/.github/workflows/scheduled-backup.yml
@C:/Users/mon pc/Desktop/ralphé_final_patch/project/scripts/backup_postgres.sh
@C:/Users/mon pc/Desktop/ralphé_final_patch/project/docs/BACKUP_RESTORE.md
@C:/Users/mon pc/Desktop/ralphé_final_patch/project/RUNBOOK.md

<interfaces>
<!-- Key env vars and secrets already used in scheduled-backup.yml -->
Existing workflow env:
  VPS_HOST: ${{ vars.VPS_HOST }}
  VPS_USER: ${{ vars.VPS_USER || 'deploy' }}
  PROJECT_DIR: ${{ vars.PROJECT_DIR || '/opt/resto' }}
  BACKUP_DIR: ${{ vars['BACKUP_DIR'] || '/opt/resto/backups' }}
  DAILY_RETENTION: 7
  WEEKLY_RETENTION: 4

Existing secrets in CI:
  secrets.VPS_SSH_KEY  -- SSH key to VPS
  secrets.ALERT_WEBHOOK_URL  -- optional alert webhook

New secrets needed (user must configure):
  secrets.S3_ACCESS_KEY_ID
  secrets.S3_SECRET_ACCESS_KEY
  secrets.BACKUP_GPG_PASSPHRASE

New vars needed:
  vars.S3_BACKUP_BUCKET     -- bucket name
  vars.S3_BACKUP_ENDPOINT   -- endpoint URL
  vars.S3_BACKUP_REGION     -- region

Backup file naming (from scheduled-backup.yml):
  BACKUP_NAME = "${BACKUP_TYPE}-$(date +%Y%m%d-%H%M%S)"
  DB dump file: "${BACKUP_NAME}-db.dump.gz"        -- exists on VPS after backup job
  Config file:  "${BACKUP_NAME}-config.tar.gz"     -- exists on VPS after backup job

Postgres restore tool: pg_restore (custom format -Fc)
  Restore command: pg_restore -U n8n -d n8n --clean --no-owner --no-acl -Fc <file>
</interfaces>
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Add S3 upload step to scheduled-backup.yml</name>
  <files>project/.github/workflows/scheduled-backup.yml</files>
  <action>
Add a new job `upload-offsite` that runs after the `backup` job succeeds. This job:

1. Checks out code and sets up SSH (same pattern as `backup` job).
2. Installs `awscli` on the GitHub Actions runner (ubuntu-latest has it, but add `pip install awscli` as a fallback).
3. Downloads the backup file FROM the VPS to the GitHub Actions runner via `scp`:
   ```
   scp -o StrictHostKeyChecking=no \
     ${VPS_USER}@${VPS_HOST}:${BACKUP_DIR}/${BACKUP_NAME}-db.dump.gz \
     /tmp/${BACKUP_NAME}-db.dump.gz
   ```
4. Verifies gzip integrity on runner: `gunzip -t /tmp/${BACKUP_NAME}-db.dump.gz`
5. Encrypts with GPG before upload (not after):
   ```
   echo "$BACKUP_GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 \
     --symmetric --cipher-algo AES256 \
     -o /tmp/${BACKUP_NAME}-db.dump.gz.gpg \
     /tmp/${BACKUP_NAME}-db.dump.gz
   ```
   Use env var `BACKUP_GPG_PASSPHRASE: ${{ secrets.BACKUP_GPG_PASSPHRASE }}` — never inline.
6. Uploads to S3:
   ```
   AWS_ACCESS_KEY_ID=${{ secrets.S3_ACCESS_KEY_ID }} \
   AWS_SECRET_ACCESS_KEY=${{ secrets.S3_SECRET_ACCESS_KEY }} \
   aws s3 cp /tmp/${BACKUP_NAME}-db.dump.gz.gpg \
     s3://${{ vars.S3_BACKUP_BUCKET }}/postgres/${BACKUP_NAME}-db.dump.gz.gpg \
     --endpoint-url ${{ vars.S3_BACKUP_ENDPOINT }} \
     --region ${{ vars.S3_BACKUP_REGION || 'auto' }}
   ```
7. Cleans up temp files: `rm -f /tmp/${BACKUP_NAME}-db.dump.gz /tmp/${BACKUP_NAME}-db.dump.gz.gpg`

CRITICAL REQUIREMENTS for this job:
- Do NOT use `continue-on-error: true` anywhere in this job.
- The job must have `needs: [backup]` and `if: needs.backup.outputs.backup_success == 'true'`
- If S3_ACCESS_KEY_ID is empty, the job should `fail` with a clear message: "S3_ACCESS_KEY_ID secret not configured — off-site upload required". Do NOT skip silently.
- Add `timeout-minutes: 10` to the job.

Also update the `summary` job at the bottom:
- Add `upload-offsite` to the `needs` array
- Add a row to the summary table: `| **Off-site Upload** | ${{ needs.upload-offsite.result || 'skipped' }} |`

Do NOT modify the existing `backup`, `pre-checks`, or `check-prerequisites` jobs.
  </action>
  <verify>
    <automated>
      # Validate YAML syntax
      python3 -c "import yaml; yaml.safe_load(open('project/.github/workflows/scheduled-backup.yml'))" && echo "YAML valid"
      # Confirm upload-offsite job exists
      grep -n "upload-offsite" project/.github/workflows/scheduled-backup.yml
      # Confirm no continue-on-error in new job
      grep -A 50 "upload-offsite:" project/.github/workflows/scheduled-backup.yml | grep "continue-on-error" && echo "FAIL: continue-on-error found" || echo "PASS: no continue-on-error"
      # Confirm aws s3 cp command is present
      grep "aws s3 cp" project/.github/workflows/scheduled-backup.yml
    </automated>
  </verify>
  <done>
    - `upload-offsite` job exists in the workflow
    - Job fails the workflow run if S3 secrets are missing (not `continue-on-error`)
    - GPG encryption happens before upload
    - No secrets are printed to logs
    - YAML parses without errors
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Write restore_drill.sh + update BACKUP_RESTORE.md + RUNBOOK.md + PATCHLOG.md</name>
  <files>
    project/scripts/restore_drill.sh,
    project/docs/BACKUP_RESTORE.md,
    project/RUNBOOK.md,
    project/PATCHLOG.md
  </files>
  <action>
**A. Create `project/scripts/restore_drill.sh`**

Script that:
1. Accepts `BACKUP_NAME` as env var or `$1` argument (e.g. `daily-20260320-030000`)
2. Downloads from S3: `aws s3 cp s3://$S3_BACKUP_BUCKET/postgres/${BACKUP_NAME}-db.dump.gz.gpg /tmp/`
3. Decrypts: `echo "$BACKUP_GPG_PASSPHRASE" | gpg --batch --passphrase-fd 0 -d /tmp/${BACKUP_NAME}-db.dump.gz.gpg > /tmp/${BACKUP_NAME}-db.dump.gz`
4. Decompresses: `gunzip /tmp/${BACKUP_NAME}-db.dump.gz` → `/tmp/${BACKUP_NAME}-db.dump`
5. Spins up a temp Postgres container: `docker run -d --name pg_drill_$$ -e POSTGRES_USER=n8n -e POSTGRES_DB=n8n -e POSTGRES_PASSWORD=drillpass postgres:15-alpine`
6. Waits for it to be ready: poll `pg_isready` with 30s timeout
7. Restores: `docker exec -i pg_drill_$$ pg_restore -U n8n -d n8n --clean --no-owner --no-acl -Fc < /tmp/${BACKUP_NAME}-db.dump`
8. Verifies minimum row counts (proves the restore is non-trivially populated):
   - `SELECT COUNT(*) FROM workflow_entity` should be > 0
   - `SELECT COUNT(*) FROM execution_entity` should be >= 0
9. Prints PASS/FAIL summary
10. Always cleans up: `docker stop pg_drill_$$ && docker rm pg_drill_$$`; `rm -f /tmp/${BACKUP_NAME}-db.dump*`

Script requirements:
- `#!/usr/bin/env bash` + `set -euo pipefail`
- Require env vars: `S3_BACKUP_BUCKET`, `S3_BACKUP_ENDPOINT`, `S3_BACKUP_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `BACKUP_GPG_PASSPHRASE` — fail fast with clear message if any are missing
- Use `trap cleanup EXIT` so temp container is always removed even on error
- Print `[DRILL PASS]` or `[DRILL FAIL]` as final line so CI can grep for it
- Do NOT hardcode any credentials

**B. Update `project/docs/BACKUP_RESTORE.md`**

Add or replace with a complete document covering:
1. Backup architecture overview (diagram in text: VPS → GitHub Actions → S3)
2. What is backed up: n8n database (`pg_dump -Fc`), `.env` + secrets archive
3. Backup schedule: daily 3 AM UTC, weekly full Sunday 4 AM UTC
4. Retention: 7 daily, 4 weekly on VPS; S3 is indefinite (configure lifecycle rule separately)
5. Off-site restore procedure (step-by-step with exact commands using `restore_drill.sh`)
6. Manual emergency restore procedure (if GitHub Actions is unavailable)
7. Verification: how to confirm the restore succeeded (row count queries)
8. Runbook links

**C. Add to `project/RUNBOOK.md`**

Add a "Restore from Off-site Backup" section with:
- When to use: VPS disk failure, ENOSPC corruption, accidental data deletion
- Prerequisites: S3 credentials, Docker, `restore_drill.sh` available
- Quick command: `BACKUP_NAME=daily-YYYYMMDD-HHMMSS bash scripts/restore_drill.sh`
- After restore: restart all services, run smoke.sh

**D. Add to `project/PATCHLOG.md`**

New entry at top:
```
## 2026-03-20 — Phase 01: Off-Site Backup Implementation
- What: Added S3 off-site upload step to scheduled-backup.yml; GPG encryption before upload; restore_drill.sh script
- Why: Local-only backup lost if VPS disk fails or ENOSPC; data loss would be total and unrecoverable
- Risk: Low — additive change; existing backup job unchanged; new upload job is independent
- Rollback: Remove upload-offsite job from scheduled-backup.yml; no VPS changes required
```
  </action>
  <verify>
    <automated>
      # Verify restore_drill.sh has correct shebang and pipefail
      head -2 project/scripts/restore_drill.sh
      # Verify DRILL PASS marker exists
      grep "DRILL PASS" project/scripts/restore_drill.sh
      # Verify trap cleanup exists
      grep "trap cleanup EXIT" project/scripts/restore_drill.sh
      # Verify BACKUP_RESTORE.md has substantial content
      wc -l project/docs/BACKUP_RESTORE.md
      # Verify RUNBOOK.md has restore section
      grep -n "Restore from Off-site" project/RUNBOOK.md
    </automated>
  </verify>
  <done>
    - `restore_drill.sh` is executable, has `set -euo pipefail`, has cleanup trap, prints `[DRILL PASS]` on success
    - `BACKUP_RESTORE.md` documents the full procedure with exact commands (minimum 60 lines)
    - `RUNBOOK.md` has "Restore from Off-site Backup" section
    - `PATCHLOG.md` has new entry at top
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <what-built>
    1. `scheduled-backup.yml` extended with `upload-offsite` job that downloads backup from VPS, GPG-encrypts, uploads to S3
    2. `scripts/restore_drill.sh` that pulls from S3, decrypts, restores to scratch Postgres container, verifies row counts
    3. `docs/BACKUP_RESTORE.md` full procedure documentation
    4. `RUNBOOK.md` restore section
    5. `PATCHLOG.md` entry
  </what-built>
  <how-to-verify>
    **Before triggering the real backup workflow:**

    1. Confirm GitHub Actions secrets are configured (Settings > Secrets > Actions):
       - `S3_ACCESS_KEY_ID` — not empty
       - `S3_SECRET_ACCESS_KEY` — not empty
       - `BACKUP_GPG_PASSPHRASE` — not empty

    2. Confirm GitHub Actions variables are configured:
       - `S3_BACKUP_BUCKET` — your bucket name
       - `S3_BACKUP_ENDPOINT` — your S3 endpoint URL
       - `S3_BACKUP_REGION` — your region

    3. Trigger `Scheduled Backup` workflow manually via GitHub Actions UI:
       - Go to Actions > Scheduled Backup > Run workflow
       - Select `backup_type: daily`
       - Confirm all 4 jobs complete green: `check-prerequisites`, `pre-checks`, `backup`, `upload-offsite`

    4. Verify backup file appears in S3 bucket at path `postgres/<backup-name>-db.dump.gz.gpg`

    5. Optionally run restore drill on VPS or local machine with proper env vars set:
       ```
       export S3_BACKUP_BUCKET=your-bucket
       export S3_BACKUP_ENDPOINT=https://...
       export S3_BACKUP_REGION=auto
       export AWS_ACCESS_KEY_ID=xxx
       export AWS_SECRET_ACCESS_KEY=xxx
       export BACKUP_GPG_PASSPHRASE=xxx
       BACKUP_NAME=daily-YYYYMMDD-HHMMSS bash project/scripts/restore_drill.sh
       ```
       Expected final line: `[DRILL PASS]`
  </how-to-verify>
  <resume-signal>Type "verified" when backup uploaded to S3 successfully, or describe any issues found.</resume-signal>
</task>

</tasks>

<verification>
Phase 01 is complete when:
- `scheduled-backup.yml` upload-offsite job exists and is not `continue-on-error`
- A test run of the workflow shows all 4 jobs green
- A backup file with `.gpg` extension appears in the S3 bucket
- `restore_drill.sh` exists and prints `[DRILL PASS]` when run against a real backup
- `docs/BACKUP_RESTORE.md` documents the full procedure
- `RUNBOOK.md` has the restore section
- `PATCHLOG.md` has the entry
</verification>

<success_criteria>
- Off-site backup: daily PostgreSQL dump is encrypted and uploaded to S3 — upload failure blocks the workflow
- Recovery is tested: `restore_drill.sh` can restore from the S3 backup and verify data integrity
- Documentation: any engineer can follow `BACKUP_RESTORE.md` to recover from total VPS loss within 30 minutes
</success_criteria>

<rollback>
**If the upload-offsite job causes issues:**
- Remove the `upload-offsite` job from `scheduled-backup.yml` — the existing backup job is untouched
- No VPS-side changes were made; rollback is a pure git revert

**If restore_drill.sh fails:**
- The script is non-destructive: it creates a temporary container (`pg_drill_$$`) and always removes it via `trap cleanup EXIT`
- If the container is left behind: `docker stop pg_drill_<pid> && docker rm pg_drill_<pid>`
- Original database is never touched by the drill script
</rollback>

<output>
After completion, create `.planning/scopes/general/phases/01-SUMMARY.md` following the summary template.
</output>
