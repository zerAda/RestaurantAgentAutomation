---
name: ci_cd_pipeline
description: Maintain the 13-workflow GitHub Actions CI/CD system with security gates, integrity checks, and deployment automation.
when_to_use:
  - Editing any .github/workflows/ file
  - Adding CI checks or gates
  - Debugging pipeline failures
  - Hardening deployments
---

# CI/CD Pipeline

## Workflow inventory

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | push/PR to main | Integrity gate, linting, unit tests, DB validation |
| `build-push-artifacts.yml` | push to main | Build Docker images, push to GHCR, sign with Cosign, SBOM, SLSA |
| `cd-deploy.yml` | workflow_run (after CI+build) | SSH deploy to VPS |
| `security-scan.yml` | push/PR/schedule | Gitleaks, Trivy, config scan, dependency scan |
| `workflow-validate.yml` | push (workflows/*.json) | n8n workflow JSON validation |
| `migration-validate.yml` | push (db/migrations/) | DB migration safety check |
| `release.yml` | workflow_dispatch | Semver release automation |
| `rollback.yml` | workflow_dispatch | Manual rollback to previous release |
| `env-sync.yml` | push | VPS env variable sync check |
| `health-monitor.yml` | schedule | Periodic health checks |
| `scheduled-backup.yml` | schedule | Automated DB backups |
| `perf-baseline.yml` | workflow_run | Performance baseline after deploy |

## Composite actions

| Action | Purpose |
|--------|---------|
| `.github/actions/setup-ssh/` | Install SSH key + known_hosts for VPS |
| `.github/actions/notify/` | Slack Block Kit + Discord embed notifications |
| `.github/actions/health-check/` | Poll health endpoint with retries |
| `.github/actions/docker-build-scan/` | Docker build with GHA cache + optional Trivy scan |

## Critical rules

1. `ci.yml` runs `scripts/integrity_gate.sh` — 10-point quality gate (MUST pass)
2. Docker tags MUST be lowercase (`github.repository_owner` needs lowercasing step)
3. Cosign signing requires matching `COSIGN_PRIVATE_KEY` + `COSIGN_PASSWORD` secrets
4. SLSA provenance uses `${{ steps.build-*.outputs.digest }}` (NOT git SHA)
5. Never write secrets to `$GITHUB_OUTPUT`
6. Trivy container scan uses `exit-code: '0'` for upstream base images (warn only)
7. Workflow validate accepts `(.active == null)` and `W_` naming prefix

## GitHub secrets required

- `VPS_SSH_KEY` — SSH key for deploy user
- `COSIGN_PRIVATE_KEY` — Cosign signing key
- `COSIGN_PASSWORD` — Cosign key password
- `COSIGN_PUBLIC_KEY` — Cosign public key

## GitHub variables required

- `VPS_HOST`, `VPS_USER`, `PROJECT_DIR`, `BACKUP_DIR`, `LOG_DIR`
- `DOMAIN`, `HEALTH_URL`

## Change management

- Atomic commits, one concern per commit
- All CI/CD changes must be tested by push (no way to test locally)
- Monitor workflow runs after push: `gh run list --repo <repo>`
- Check failed run logs: `gh run view <id> --log-failed`

## Deliverables

- Pipeline diff
- Verification: all triggered workflows pass green
- Rollback: `git revert` the CI change
