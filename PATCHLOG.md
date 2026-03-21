# PATCHLOG — Resto Bot

This file tracks significant infrastructure and platform patches applied to the project.
Each entry documents what changed, why, the risk level, and how to roll back.

---

## 2026-03-21 — Phase 01: Off-Site Backup Implementation

- **What**: Added `upload-offsite` job to `.github/workflows/scheduled-backup.yml`; GPG AES-256 encryption before upload; `scripts/restore_drill.sh` automated restore verification script; updated `docs/BACKUP_RESTORE.md` and `docs/RUNBOOK.md`
- **Why**: Local-only backup is insufficient — if the VPS 119 GB disk fails or hits ENOSPC (a documented recurring risk), both the live database and the only backup copy are lost together. Total data loss would be unrecoverable. Off-site S3 backup closes this gap.
- **Risk**: Low — additive change only. The existing `backup` job is untouched. The new `upload-offsite` job is independent and only runs after a successful backup. `restore_drill.sh` is non-destructive (uses a throwaway container).
- **Rollback**: Remove the `upload-offsite` job from `.github/workflows/scheduled-backup.yml` and revert `summary` job `needs` array. No VPS-side changes required. `git revert` of the Phase 01 commit is sufficient.
- **User action required**: Configure GitHub Actions secrets `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `BACKUP_GPG_PASSPHRASE` and variables `S3_BACKUP_BUCKET`, `S3_BACKUP_ENDPOINT`, `S3_BACKUP_REGION` before the upload-offsite job will succeed.
