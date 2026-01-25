#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== RESTO BOT - Integrity Gate =="

fail() { echo "❌ $*" >&2; exit 1; }

echo "\n[1/8] Bash syntax check"
bash -n scripts/*.sh || fail "bash -n failed"

echo "\n[2/8] Secret scan (forbidden placeholder CHANGE_ME)"
if grep -R --line-number --fixed-string "CHANGE_ME" \
  --exclude-dir=docs --exclude-dir=patches \
  --exclude=PATCH.diff --exclude=PATCHLOG.md --exclude=TEST_REPORT.md --exclude=ROLLBACK.md \
  --exclude=integrity_gate.sh -- . >/dev/null 2>&1; then
  echo "Found forbidden placeholder(s):"
  grep -R --line-number --fixed-string "CHANGE_ME" \
    --exclude-dir=docs --exclude-dir=patches \
    --exclude=PATCH.diff --exclude=PATCHLOG.md --exclude=TEST_REPORT.md --exclude=ROLLBACK.md \
    --exclude=integrity_gate.sh -- . || true
  fail "CHANGE_ME placeholder found"
fi

echo "\n[3/8] Workflow JSON validation"
for wf in workflows/*.json; do
  jq -e '.name and (.nodes|type=="array") and (.connections|type=="object") and (.active|type=="boolean")' "$wf" >/dev/null \
    || fail "Invalid workflow JSON: $wf"

  base="$(basename "$wf")"
  # inbound parse nodes must gate query tokens + enforce scopes
  if [[ "$base" == "W1_IN_WA.json" || "$base" == "W2_IN_IG.json" || "$base" == "W3_IN_MSG.json" ]]; then
    code="$(jq -r '.nodes[] | select(.name=="B0 - Parse & Canonicalize") | .parameters.jsCode' "$wf")"
    echo "$code" | grep -q "ALLOW_QUERY_TOKEN" || fail "$wf: ALLOW_QUERY_TOKEN gating missing"

    # token gate must include scopeOk
    jq -e '.nodes[] | select(.name=="B0 - Token OK?") | .parameters.conditions.boolean | map(.value1) | any(.=="={{$json._auth.scopeOk}}")' "$wf" >/dev/null \
      || fail "$wf: missing scopeOk enforcement in Token OK gate"

    # deny logger must support scope-aware event_type (parameterized)
    jq -e '.nodes[] | select(.name=="B0 - Log Deny (DB)") | .parameters.query | contains("$6")' "$wf" >/dev/null \
      || fail "$wf: Log Deny must parameterize event_type"

    jq -e '.nodes[] | select(.name=="B0 - Contract Valid?")' "$wf" >/dev/null || fail "$wf: missing Contract gate"
    jq -e '.nodes[] | select(.name=="RESP - 200 OK")' "$wf" >/dev/null || fail "$wf: missing RESP - 200 OK"
    jq -e '.nodes[] | select(.name=="RESP - 400 Invalid Payload")' "$wf" >/dev/null || fail "$wf: missing RESP - 400 Invalid Payload"
    jq -e '.nodes[] | select(.name=="IN - Webhook" and .parameters.responseMode=="responseNode")' "$wf" >/dev/null \
      || fail "$wf: webhook responseMode must be responseNode"
  fi

done

echo "\n[4/8] JSON Schema unit tests"
python3 scripts/validate_contracts.py || fail "Schema unit tests failed"

echo "\n[4b] L10N unit tests (Darija + template rendering)"
python3 scripts/test_darja_intents.py || fail "Darija intent tests failed"
python3 scripts/test_template_render.py || fail "Template rendering tests failed"
python3 scripts/test_l10n_script_detection.py || fail "L10N script detection tests failed"

echo "\n[5/8] DB bootstrap ordering check"
orders_line=$(grep -n -- "CREATE TABLE IF NOT EXISTS orders" db/bootstrap.sql | head -n1 | cut -d: -f1 || true)
outbox_line=$(grep -n -- "CREATE TABLE IF NOT EXISTS outbound_messages" db/bootstrap.sql | head -n1 | cut -d: -f1 || true)
if [[ -n "$orders_line" && -n "$outbox_line" ]]; then
  if (( orders_line > outbox_line )); then
    fail "db/bootstrap.sql: orders must be created before outbound_messages (FK dependency)"
  fi
else
  fail "db/bootstrap.sql: could not locate orders/outbound_messages definitions"
fi

echo "\n[6/8] Required files presence"

# Existing patch artifacts (SYSTEM2)
[[ -f db/migrations/2026-01-22_p1_db_indexes_retention.sql ]] || fail "Missing migration: 2026-01-22_p1_db_indexes_retention.sql"
[[ -f db/migrations/2026-01-22_p1_event_types_constraints.sql ]] || fail "Missing migration: 2026-01-22_p1_event_types_constraints.sql"
[[ -f db/migrations/2026-01-22_p1_arch_002_contract_slo_event_types.sql ]] || fail "Missing migration: 2026-01-22_p1_arch_002_contract_slo_event_types.sql"

# Release-grade (SYSTEM3)
[[ -f db/migrations/2026-01-22_p1_opssecqa_scopes_admin_audit.sql ]] || fail "Missing migration: 2026-01-22_p1_opssecqa_scopes_admin_audit.sql"
[[ -f scripts/backup_postgres.sh ]] || fail "Missing script: scripts/backup_postgres.sh"
[[ -f scripts/restore_postgres.sh ]] || fail "Missing script: scripts/restore_postgres.sh"
[[ -f scripts/backup_redis.sh ]] || fail "Missing script: scripts/backup_redis.sh"
[[ -f scripts/test_harness.sh ]] || fail "Missing script: scripts/test_harness.sh"
[[ -f docker/docker-compose.test.yml ]] || fail "Missing compose: docker/docker-compose.test.yml"
[[ -f infra/gateway/nginx.test.conf ]] || fail "Missing gateway conf: infra/gateway/nginx.test.conf"
[[ -f docs/BACKUP_RESTORE.md ]] || fail "Missing docs: docs/BACKUP_RESTORE.md"
[[ -f docs/RUNBOOKS.md ]] || fail "Missing docs: docs/RUNBOOKS.md"
[[ -f tests/fixtures/00_seed_api_clients.sql ]] || fail "Missing fixture: tests/fixtures/00_seed_api_clients.sql"
[[ -f workflows/W9_ADMIN_PING.json ]] || fail "Missing workflow: workflows/W9_ADMIN_PING.json"

# Validate W8 contains retention nodes
jq -e '.nodes[] | select(.name=="R1 - Retention Purge (Daily 03:30)")' workflows/W8_OPS.json >/dev/null \
  || fail "W8_OPS missing Retention Purge schedule"

# Delivery EPIC2 workflows
[[ -f workflows/W10_CUSTOMER_DELIVERY_QUOTE.json ]] || fail "Missing workflow: workflows/W10_CUSTOMER_DELIVERY_QUOTE.json"
[[ -f workflows/W11_ADMIN_DELIVERY_ZONES.json ]] || fail "Missing workflow: workflows/W11_ADMIN_DELIVERY_ZONES.json"

# Delivery docs/templates
[[ -f docs/DELIVERY.md ]] || fail "Missing docs: docs/DELIVERY.md"
[[ -f templates/delivery/clarify_fr.txt ]] || fail "Missing template: templates/delivery/clarify_fr.txt"
[[ -f templates/delivery/clarify_ar.txt ]] || fail "Missing template: templates/delivery/clarify_ar.txt"
[[ -f templates/delivery/clarify_darja.txt ]] || fail "Missing template: templates/delivery/clarify_darja.txt"


# EPIC5 L10N
[[ -f db/migrations/2026-01-23_p2_epic5_l10n.sql ]] || fail "Missing migration: 2026-01-23_p2_epic5_l10n.sql"
[[ -f docs/L10N.md ]] || fail "Missing docs: docs/L10N.md"
[[ -f docs/ROLLBACK_EPIC5_L10N.md ]] || fail "Missing docs: docs/ROLLBACK_EPIC5_L10N.md"
[[ -f scripts/test_darja_intents.py ]] || fail "Missing script: scripts/test_darja_intents.py"
[[ -f scripts/test_template_render.py ]] || fail "Missing script: scripts/test_template_render.py"
[[ -f scripts/test_l10n_script_detection.py ]] || fail "Missing script: scripts/test_l10n_script_detection.py"
[[ -f tests/darja_phrases.json ]] || fail "Missing test data: tests/darja_phrases.json"

# EPIC3 Tracking
[[ -f db/migrations/2026-01-22_p2_epic3_tracking.sql ]] || fail "Missing migration: 2026-01-22_p2_epic3_tracking.sql"
[[ -f workflows/W12_ADMIN_ORDERS.json ]] || fail "Missing workflow: workflows/W12_ADMIN_ORDERS.json"
[[ -f docs/TRACKING.md ]] || fail "Missing docs: docs/TRACKING.md"
[[ -f docs/ROLLBACK_EPIC3_TRACKING.md ]] || fail "Missing docs: docs/ROLLBACK_EPIC3_TRACKING.md"
[[ -f templates/whatsapp/WA_ORDER_STATUS_templates.fr.json ]] || fail "Missing template: templates/whatsapp/WA_ORDER_STATUS_templates.fr.json"
[[ -f templates/whatsapp/WA_ORDER_STATUS_templates.ar.json ]] || fail "Missing template: templates/whatsapp/WA_ORDER_STATUS_templates.ar.json"

# EPIC6 Support
[[ -f db/migrations/2026-01-23_p2_epic6_support.sql ]] || fail "Missing migration: 2026-01-23_p2_epic6_support.sql"
[[ -f workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json ]] || fail "Missing workflow: workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json"
[[ -f docs/SUPPORT.md ]] || fail "Missing docs: docs/SUPPORT.md"
[[ -f docs/ROLLBACK_EPIC6_SUPPORT.md ]] || fail "Missing docs: docs/ROLLBACK_EPIC6_SUPPORT.md"

# P0 Security (v3.2.3)
[[ -f infra/gateway/nginx.conf ]] || fail "Missing security file: infra/gateway/nginx.conf"
[[ -f db/migrations/2026-01-23_p0_sec02_meta_replay.sql ]] || fail "Missing migration: 2026-01-23_p0_sec02_meta_replay.sql"
[[ -f scripts/smoke_security_gateway.sh ]] || fail "Missing script: scripts/smoke_security_gateway.sh"

# P0-SEC-01: Verify nginx.conf is mounted in prod compose
grep -q "nginx.conf" docker-compose.hostinger.prod.yml || fail "P0-SEC-01: nginx.conf not mounted in prod compose"

# P0-L10N-01: Verify L10N defaults
grep -q "L10N_ENABLED:-true" docker-compose.hostinger.prod.yml || fail "P0-L10N-01: L10N_ENABLED not defaulting to true"

echo "\n[7/8] VERSION check"
VERSION=$(cat VERSION 2>/dev/null || echo "0.0.0")
if [[ "$VERSION" == "3.2.2" ]]; then
  echo "VERSION: $VERSION ✓"
else
  echo "WARNING: VERSION is $VERSION (expected 3.2.2 for P0 security release)"
fi

echo "\n[8/9] Compose YAML parse (best-effort)"
python3 - <<'PY'
import sys
from pathlib import Path
try:
  import yaml
except Exception:
  print('PyYAML not installed: skipping YAML parse')
  sys.exit(0)

files = [
  Path('docker-compose.hostinger.prod.yml'),
  Path('docker/docker-compose.yml'),
  Path('docker/docker-compose.test.yml'),
]
for f in files:
  if not f.exists():
    continue
  try:
    data = yaml.safe_load(f.read_text())
    assert isinstance(data, dict) and 'services' in data
  except Exception as e:
    raise SystemExit(f"Invalid YAML in {f}: {e}")
print('YAML parse OK')
PY

echo "\n[9/10] Backup/restore scripts lint (basic)"
# Ensure scripts have strict mode and no obvious footguns
grep -q "set -euo pipefail" scripts/backup_postgres.sh || fail "backup_postgres.sh missing strict mode"
grep -q "CONFIRM_RESTORE" scripts/restore_postgres.sh || fail "restore_postgres.sh missing CONFIRM_RESTORE gate"

echo "\n[10/10] P0 Security Config Validation"
# Check .env.example has all P0 security flags
grep -q "LEGACY_SHARED_ALLOWED" config/.env.example || fail ".env.example missing LEGACY_SHARED_ALLOWED"
grep -q "META_SIGNATURE_REQUIRED" config/.env.example || fail ".env.example missing META_SIGNATURE_REQUIRED"
grep -q "STRICT_AR_OUT" config/.env.example || fail ".env.example missing STRICT_AR_OUT"
grep -q "ADMIN_WA_AUDIT_ENABLED" config/.env.example || fail ".env.example missing ADMIN_WA_AUDIT_ENABLED"

echo "\n✅ Integrity Gate PASS (v3.2.3 P0 Security)"
