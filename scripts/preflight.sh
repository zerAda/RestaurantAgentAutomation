#!/usr/bin/env bash
set -euo pipefail

echo "== RESTO BOT v3.0 - Preflight =="

REQ_VARS=(
  DOMAIN_NAME SSL_EMAIL CONSOLE_SUBDOMAIN API_SUBDOMAIN
  ADMIN_ALLOWED_IPS TRAEFIK_TRUSTED_IPS
  N8N_VERSION
)

OPT_VARS=(
  WEBHOOK_SHARED_TOKEN
  ALLOWED_AUDIO_DOMAINS
  OUTBOX_MAX_ATTEMPTS OUTBOX_BASE_DELAY_SEC OUTBOX_MAX_DELAY_SEC
)

missing=0
for v in "${REQ_VARS[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "❌ Missing env: $v"
    missing=1
  fi
done

for v in "${OPT_VARS[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "⚠️  Optional env not set: $v"
  fi
done

# Hard safety checks for allowlists in prod
bad_cidr_regex='(^|,|\s)(0\.0\.0\.0/0|::/0)(,|\s|$)'
if [[ "${ADMIN_ALLOWED_IPS:-}" =~ $bad_cidr_regex ]]; then
  echo "❌ ADMIN_ALLOWED_IPS must not contain 0.0.0.0/0 or ::/0"
  missing=1
fi
if [[ "${ADMIN_ALLOWED_IPS:-}" =~ (10\.0\.0\.0/8|192\.168\.0\.0/16|172\.16\.0\.0/12) ]]; then
  echo "❌ ADMIN_ALLOWED_IPS must not include private ranges in prod. Use ONLY public /32 IPs."
  missing=1
fi

if [[ "${TRAEFIK_TRUSTED_IPS:-}" =~ $bad_cidr_regex ]]; then
  echo "❌ TRAEFIK_TRUSTED_IPS must not contain 0.0.0.0/0 or ::/0"
  missing=1
fi

# Secrets (file-based)
REQ_FILES=(
  ./secrets/postgres_password
  ./secrets/n8n_encryption_key
  ./secrets/traefik_usersfile
)
for f in "${REQ_FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "❌ Missing file: $f"
    missing=1
  fi
done

if [[ "$missing" -eq 1 ]]; then
  echo "Preflight failed."
  exit 1
fi

echo "✅ Env + secrets OK"
echo "Tip: run docker compose pull && docker compose up -d"
