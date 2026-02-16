---
name: secrets_data_protection
description: Prevent secret leakage, manage rotation, protect PII, enforce data retention.
when_to_use:
  - Adding integrations or API keys
  - Debugging auth issues
  - Preparing for audit
  - Reviewing data handling
  - Token rotation
---

# Secrets & Data Protection

## Secret storage locations

| Secret type | Where stored | Reference |
|-------------|-------------|-----------|
| VPS SSH key | GitHub Actions secret `VPS_SSH_KEY` | `.github/workflows/cd-deploy.yml` |
| Cosign keypair | GitHub secrets + VPS `/opt/resto/shared/cosign/` | `build-push-artifacts.yml` |
| GHCR token | `GITHUB_TOKEN` (automatic) | `build-push-artifacts.yml` |
| Webhook tokens | `.env` on VPS `/opt/resto/shared/.env` | `config/.env.example` |
| DB password | `.env` (never in compose directly) | `docker-compose.hostinger.prod.yml` |
| API keys | `.env` (Chargily, OpenAI, Replicate, Meta) | `config/.env.example` |

## Rules

1. No secrets in git (enforced by `.github/workflows/security-scan.yml` Gitleaks job)
2. No secrets in logs (redact `x-webhook-token`, `Authorization`, API keys)
3. No secrets in GitHub Actions step outputs (never `echo "secret=..." >> $GITHUB_OUTPUT`)
4. `.env` is gitignored; `config/.env.example` is the template (uses `CHANGE_ME` placeholders)
5. `integrity_gate.sh` scans for `CHANGE_ME` in non-excluded files

## Rotation procedure

1. Generate new credential
2. Deploy to VPS `.env` (and GitHub secrets if applicable)
3. Restart affected services: `docker compose up -d <service>`
4. Verify with smoke test
5. Revoke old credential
6. Update `config/.env.example` if variable name changed

## PII handling

- Phone numbers, names, addresses stored in Postgres `orders`, `customers` tables
- Logs must NOT contain PII (check nginx access log format, n8n execution logs)
- Retention: purged by `W8_OPS.json` retention node (`R1 - Retention Purge`)
- Admin access: protected by IP allowlist + BasicAuth on console/admin

## CI enforcement

- Gitleaks: `.github/workflows/security-scan.yml` job `secret-scan`
- Custom patterns: AWS keys, private key headers
- `integrity_gate.sh` check 2/10: scans for `CHANGE_ME` placeholders

## Deliverables

- Updated `config/.env.example` if env vars change
- Redaction audit (verify logs don't leak secrets/PII)
- Rotation verification (smoke test after rotation)
