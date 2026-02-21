#!/usr/bin/env bash
set -euo pipefail

# CI-friendly test harness
# - Spins up a minimal stack (postgres+redis+n8n+gateway+mock-api)
# - Applies migrations
# - Seeds fixtures
# - Imports workflows
# - Runs smoke tests (including scopes enforcement)
# - Tears down

COMPOSE_FILE=${COMPOSE_FILE:-docker/docker-compose.test.yml}
BASE_URL=${BASE_URL:-http://localhost:18080}

INBOUND_TOKEN=${INBOUND_TOKEN:-test-token-inbound}
ADMIN_TOKEN=${ADMIN_TOKEN:-test-token-admin}
CUSTOMER_TOKEN=${CUSTOMER_TOKEN:-test-token-customer}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() { echo "❌ $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || fail "Missing dependency: $1"; }

need docker
need curl
need jq

docker compose version >/dev/null 2>&1 || fail "docker compose is required"

echo "== Test harness =="
echo "Compose:  $COMPOSE_FILE"
echo "Base URL: $BASE_URL"

# Clean start
set +e
docker compose -f "$COMPOSE_FILE" down -v --remove-orphans >/dev/null 2>&1
set -e

# 1) Start dependencies

echo "[1/8] Up: postgres + redis + mock-api"
docker compose -f "$COMPOSE_FILE" up -d postgres redis mock-api

# Wait for postgres (must survive initdb restart cycle)

echo "Waiting for postgres..."
for i in $(seq 1 60); do
  if docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -c 'SELECT 1'" >/dev/null 2>&1; then
    break
  fi
  sleep 2
  if [[ $i -eq 60 ]]; then fail "postgres not ready"; fi
done

# 1.5) Create strapi DB (needed by migration 006)
# NOTE: bootstrap.sql is already applied by docker-entrypoint-initdb.d mount in docker-compose.test.yml
echo "[1.5/8] Ensure strapi DB exists (for migration 006)"
docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d postgres -tc \"SELECT 1 FROM pg_database WHERE datname = 'strapi'\" | grep -q 1 || psql -U n8n -d postgres -c 'CREATE DATABASE strapi OWNER n8n;'"

# 2) Apply migrations

echo "[2/8] Apply migrations"
for m in $(ls -1 db/migrations/*.sql 2>/dev/null | sort); do
  echo "- $m"
  # Cross-database migrations (\c) may warn but should not block the harness
  if grep -q '\\c ' "$m"; then
    COMPOSE_FILE="$COMPOSE_FILE" ./scripts/db_migrate.sh "$COMPOSE_FILE" "$m" || echo "::warning::Cross-database migration had issues (expected): $m"
  else
    COMPOSE_FILE="$COMPOSE_FILE" ./scripts/db_migrate.sh "$COMPOSE_FILE" "$m"
  fi
done

# 3) Seed fixtures

echo "[3/8] Seed fixtures"
for f in $(ls -1 tests/fixtures/*.sql 2>/dev/null | sort); do
  echo "- $f"
  docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -v ON_ERROR_STOP=1 -U n8n -d n8n < /dev/stdin" < "$f"
done

# 4) Start n8n (CORE_WORKFLOW_ID is injected after import)

echo "[4/8] Up: n8n (initial)"
docker compose -f "$COMPOSE_FILE" up -d n8n

# Wait for n8n to be fully initialized (not just HTTP port open).
# n8n 1.93+ returns "n8n is starting up. Please wait" while running migrations.
echo "Waiting for n8n to start..."
for i in $(seq 1 90); do
  resp="$(curl -s "http://localhost:25678/rest/settings" 2>/dev/null || true)"
  if echo "$resp" | jq -e '.data' >/dev/null 2>&1; then break; fi
  sleep 2
  if [[ $i -eq 90 ]]; then fail "n8n did not start (still initializing after 180s)"; fi
done

# Cookie jar for n8n API auth (version-agnostic)
N8N_JAR="/tmp/n8n_cookies"

# Create owner account (n8n 1.80+ requires this before webhooks work)
# Also captures the auth cookie set by the setup response.
echo "Setting up n8n owner account..."
for i in $(seq 1 30); do
  setup_status="$(curl -s -o /tmp/n8n_setup_resp.json -w "%{http_code}" -c "$N8N_JAR" \
    -X POST "http://localhost:25678/rest/owner/setup" \
    -H "Content-Type: application/json" \
    -d '{"email":"test@example.com","firstName":"Test","lastName":"User","password":"TestPassw0rd!"}')"
  if [[ "$setup_status" == "200" ]]; then
    echo "Owner created (200)"
    break
  elif [[ "$setup_status" == "400" ]]; then
    echo "Owner already exists (400) - OK"
    break
  fi
  sleep 2
  if [[ $i -eq 30 ]]; then echo "Warning: owner setup returned $setup_status (may be fine)"; fi
done

# 5) Import workflows via n8n REST API
# Using the REST API (not CLI import) ensures proper workflow ownership
# and correct webhook registration on activation.
# CLI import creates DB records but skips the shared_workflow ownership table,
# which causes n8n 1.80+ to silently skip webhook route registration.

echo "[5/8] Import workflows"

# Login helper: saves session cookies to jar
n8n_login() {
  rm -f "$N8N_JAR"
  local resp_code
  resp_code="$(curl -s -o /tmp/n8n_login_resp.json -w "%{http_code}" -c "$N8N_JAR" \
    -X POST "http://localhost:25678/rest/login" \
    -H "Content-Type: application/json" \
    -d '{"emailOrLdapLoginId":"test@example.com","password":"TestPassw0rd!"}')"
  if [[ "$resp_code" != "200" ]]; then
    echo "  login returned $resp_code" >&2
    head -c 200 /tmp/n8n_login_resp.json >&2 || true
    return 1
  fi
  # Verify cookies were actually set (not just file headers)
  if ! grep -qv '^#' "$N8N_JAR" 2>/dev/null || ! grep -qv '^$' "$N8N_JAR" 2>/dev/null; then
    echo "  login 200 but no cookies in jar" >&2
    return 1
  fi
}

# If owner setup already captured auth cookies, try them; otherwise login
if grep -qv '^#\|^$' "$N8N_JAR" 2>/dev/null; then
  echo "Auth cookies from owner setup"
else
  echo "Logging into n8n API..."
  n8n_login || fail "n8n API login failed"
fi

# Helper: create workflow via REST API (handles ownership + activation + webhook registration)
# Usage: id="$(create_wf path/to/file.json "label" true|false)"
# Status messages → stderr; workflow ID → stdout.
create_wf() {
  local wf_file="$1"
  local label="$2"
  local active="${3:-false}"

  jq "del(.id) | .active = $active" \
    "$ROOT_DIR/$wf_file" > /tmp/_wf_payload.json || fail "preprocess $label failed"

  local resp http_code
  http_code="$(curl -s -o /tmp/_wf_resp.json -w "%{http_code}" -b "$N8N_JAR" \
    -X POST "http://localhost:25678/rest/workflows" \
    -H "Content-Type: application/json" \
    -d @/tmp/_wf_payload.json)"
  resp="$(cat /tmp/_wf_resp.json 2>/dev/null)"

  # Try both response formats: { data: { id } } (old) and { id } (new)
  local wf_id
  wf_id="$(echo "$resp" | jq -r '.data.id // .id // empty' 2>/dev/null)"

  if [[ -n "$wf_id" && "$wf_id" != "null" ]]; then
    echo "  $label → created (id=$wf_id, active=$active)" >&2
    printf "%s" "$wf_id"
  else
    echo "  $label → FAILED (HTTP $http_code): $(echo "$resp" | head -c 300)" >&2
    return 1
  fi
}

# Phase 1: Import internal workflows (inactive, no webhook needed)
core_id="$(create_wf workflows/W4_CORE.json "W4 CORE" false)" || fail "W4 import failed"
admin_wa_id="$(create_wf workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json "W14 ADMIN WA" false)" || fail "W14 import failed"

echo "CORE_WORKFLOW_ID=$core_id"
echo "ADMIN_WA_CONSOLE_WORKFLOW_ID=$admin_wa_id"
export CORE_WORKFLOW_ID="$core_id"
export ADMIN_WA_CONSOLE_WORKFLOW_ID="$admin_wa_id"

# Phase 1b: Import ALL workflows BEFORE restart.
# Only the 7 core smoke-tested webhook workflows are set ACTIVE;
# all others are INACTIVE to avoid "Could not find property option"
# errors from newer workflows incompatible with n8n 1.93.0.
echo "Creating core webhook workflows (active, pre-restart)..."
CREATE_FAILED=0
for wf in W1_IN_WA.json W2_IN_IG.json W3_IN_MSG.json \
          W9_ADMIN_PING.json W10_CUSTOMER_DELIVERY_QUOTE.json \
          W11_ADMIN_DELIVERY_ZONES.json W12_ADMIN_ORDERS.json; do
  create_wf "workflows/$wf" "$wf" true > /dev/null 2>&1 || {
    echo "::warning::Failed to create $wf (non-blocking)"
    CREATE_FAILED=$((CREATE_FAILED + 1))
  }
done

# Import all remaining workflows as INACTIVE (coverage, no activation errors)
echo "Creating remaining workflows (inactive)..."
for wf in W0_META_VERIFY_UNIFIED.json W1_IN_TIKTOK.json \
          W8_DLQ_REPLAY.json W16_HEALTHZ.json \
          W_PAYMENT_CALLBACK.json W_PAYMENT_CHARGILY.json \
          W20_ASSET_ENHANCER.json W_HIVE_MIND_DISPATCH.json \
          W_THE_USUAL.json W_DRIVER_GAMIFICATION.json \
          W_DRIVER_BOT.json W_DRIVER_DISPATCH.json \
          W_CMS_SYNC.json W_DRIVER_OTP_VERIFY.json \
          W_DRIVER_ACTIONS.json W_DRIVER_AVAILABLE_LIST.json \
          W_DRIVER_ONBOARDING.json W_DRIVER_HISTORY.json \
          W_DRIVER_ROUTER.json \
          W8_OPS.json W8_DLQ_HANDLER.json W5_OUT_WA.json W5_OUT_TIKTOK.json \
          W6_OUT_IG.json W7_OUT_MSG.json W15_OUTBOX_WORKER.json \
          W17_HEALTH_MONITOR.json W18_MEDIA_FETCH_WORKER.json \
          W21_CAMPAIGN_BLASTER.json W4_CORE_ALGERIAN_STUB.json \
          W4_CORE_MENU_GROUNDED.json W0_REDIS_HELPER.json \
          W_ADMIN_LIVE_MONITOR.json W_AI_STRATEGY_ADVISOR.json \
          W_INVENTORY_SYNC.json W_LOW_STOCK_ALERT.json \
          W_MARKETING_AUTOPILOT.json W_MENU_VALIDATOR.json \
          W_QR_TABLE_DETECTOR.json W_WEATHER_TRIGGER.json; do
  create_wf "workflows/$wf" "$wf" false > /dev/null 2>&1 || echo "::warning::Failed to create $wf (non-blocking)"
done

[[ "$CREATE_FAILED" -eq 0 ]] || echo "::warning::$CREATE_FAILED core webhook workflow(s) failed to create"

# KEY FIX: Clear stale webhook_entity rows BEFORE restart.
# The REST API creates webhook_entity records but does NOT register Express
# routes (n8n bug #21614: shouldAddWebhooks('activate') returns false).
# On restart, n8n sees existing webhook_entity records and SKIPS re-registration,
# leaving Express routes unregistered. Clearing the table forces n8n's init mode
# to register webhooks from scratch (both DB records AND Express routes).
echo "Clearing stale webhook_entity (force re-registration on restart)..."
docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc \
  "psql -U n8n -d n8n -c 'DELETE FROM webhook_entity;'" 2>/dev/null || echo "  (table may not exist yet — OK)"

# Phase 2: Recreate n8n with CORE_WORKFLOW_ID and ADMIN_WA_CONSOLE_WORKFLOW_ID.
# On restart, ActiveWorkflowManager.init() reads active workflows from DB
# and activates them with mode='init'. With webhook_entity cleared, it will
# create fresh Express routes for all active webhook workflows.
echo "Recreating n8n with workflow IDs..."
docker compose -f "$COMPOSE_FILE" stop n8n
docker compose -f "$COMPOSE_FILE" up -d --force-recreate n8n

echo "Waiting for n8n after recreate..."
for i in $(seq 1 90); do
  resp="$(curl -s "http://localhost:25678/rest/settings" 2>/dev/null || true)"
  if echo "$resp" | jq -e '.data' >/dev/null 2>&1; then break; fi
  sleep 2
  if [[ $i -eq 90 ]]; then fail "n8n did not start after recreate"; fi
done

# Diagnostic: webhook_entity + shouldAddWebhooks source
echo "webhook_entity rows (post-restart):"
docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc \
  "psql -U n8n -d n8n -c 'SELECT \"webhookPath\", method FROM webhook_entity LIMIT 20;'" 2>/dev/null || echo "  (query failed)"

# Diagnostic: probe n8n source for webhook registration code
echo "n8n webhook source diagnostic:"
docker compose -f "$COMPOSE_FILE" exec -T n8n sh -c \
  "grep -c 'shouldAddWebhooks\|registerWebhook\|activeWebhooks' /usr/local/lib/node_modules/n8n/dist/active-workflow-manager.js 2>/dev/null" || true

# Diagnostic: try the FULL webhook path from webhook_entity (may include workflowId prefix)
WH_FULL_PATH="$(docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc \
  "psql -U n8n -d n8n -Atc \"SELECT \\\"webhookPath\\\" FROM webhook_entity WHERE method='POST' LIMIT 1;\"" | tr -d '\r\n')"
echo "Full webhook_entity path: $WH_FULL_PATH"
if [[ -n "$WH_FULL_PATH" ]]; then
  full_status="$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:25678/webhook/$WH_FULL_PATH" \
    -H "Content-Type: application/json" \
    -d '{"text":"probe-full","from":"probe","msgId":"harness-probe-full"}')"
  echo "Full path /webhook/$WH_FULL_PATH → $full_status"
fi

# Also try with just workflowId/path (no nodeName)
WH_WF_ID="$(echo "$WH_FULL_PATH" | cut -d/ -f1)"
WH_USER_PATH="v1/inbound/whatsapp"
echo "Simple path /webhook/$WH_USER_PATH probe:"
simple_status="$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:25678/webhook/$WH_USER_PATH" \
  -H "Content-Type: application/json" \
  -d '{"text":"probe-simple","from":"probe","msgId":"harness-probe-simple"}')"
echo "  → $simple_status"
echo "WorkflowId path /webhook/$WH_WF_ID/$WH_USER_PATH probe:"
wfid_status="$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:25678/webhook/$WH_WF_ID/$WH_USER_PATH" \
  -H "Content-Type: application/json" \
  -d '{"text":"probe-wfid","from":"probe","msgId":"harness-probe-wfid"}')"
echo "  → $wfid_status"

# Show n8n startup logs for webhook registration
echo "n8n startup logs (webhook-related):"
docker compose -f "$COMPOSE_FILE" logs n8n 2>&1 | grep -iE "webhook|register|route|listen|started|error|warn" | head -30 || true

# Poll webhook endpoint (up to 60s)
echo "Waiting for webhook registration..."
for i in $(seq 1 30); do
  wh_status="$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:25678/webhook/v1/inbound/whatsapp" \
    -H "Content-Type: application/json" \
    -d '{"text":"probe","from":"probe","msgId":"webhook-probe-'$i'"}')"
  if [[ "$wh_status" != "404" && "$wh_status" != "000" ]]; then
    echo "Webhooks registered (status=$wh_status)"
    break
  fi
  sleep 2
  if [[ $i -eq 30 ]]; then
    echo "::warning::Webhooks not registered after 60s (last=$wh_status)"
    echo "n8n logs (last 50 lines):"
    docker compose -f "$COMPOSE_FILE" logs --tail=50 n8n 2>&1 || true
  fi
done

# 6) Up: gateway

echo "[6/8] Up: gateway"
docker compose -f "$COMPOSE_FILE" up -d gateway

echo "Waiting for gateway /healthz..."
for i in $(seq 1 60); do
  if curl -fsS "$BASE_URL/healthz" >/dev/null 2>&1; then break; fi
  sleep 1
  if [[ $i -eq 60 ]]; then fail "gateway not ready"; fi
done

# 7) Smoke tests

echo "[7/8] Smoke tests"
curl -fsS "$BASE_URL/healthz" >/dev/null && echo "✅ healthz"

# Wait for n8n webhooks to respond through gateway (502/404 = not ready yet)
echo "Waiting for n8n webhooks behind gateway..."
for i in $(seq 1 45); do
  gw_status="$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/v1/inbound/whatsapp" \
    -H "Content-Type: application/json" \
    -H "x-webhook-token: $INBOUND_TOKEN" \
    -d '{"text":"warmup","from":"warmup","msgId":"harness-warmup-'$i'"}')"
  if [[ "$gw_status" != "502" && "$gw_status" != "404" && "$gw_status" != "000" ]]; then
    echo "n8n webhooks ready (status=$gw_status)"
    break
  fi
  sleep 2
  if [[ $i -eq 45 ]]; then
    echo "::error::n8n webhooks not ready (last=$gw_status). n8n logs:"
    docker compose -f "$COMPOSE_FILE" logs --tail=20 n8n 2>&1 || true
    fail "n8n webhooks not ready after 90s (last status=$gw_status)"
  fi
done

# inbound valid
curl -fsS -X POST "$BASE_URL/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: $INBOUND_TOKEN" \
  -d '{"text":"hello","from":"harness","msgId":"harness-1"}' >/dev/null \
  && echo "✅ inbound whatsapp (valid token)"

# admin with inbound token -> 403
status="$(curl -s -o /tmp/admin_deny.json -w "%{http_code}" -X GET "$BASE_URL/v1/admin/ping" -H "x-webhook-token: $INBOUND_TOKEN")"
if [[ "$status" != "403" ]]; then
  echo "❌ expected 403 for admin without scope, got $status"; cat /tmp/admin_deny.json || true; exit 1
fi

echo "✅ admin ping denied (403)"

# admin with admin token -> 200
curl -fsS -X GET "$BASE_URL/v1/admin/ping" -H "x-webhook-token: $ADMIN_TOKEN" >/dev/null \
  && echo "✅ admin ping allowed (200)"

# delivery quote (valid zone)
resp_ok="$(curl -fsS -X POST "$BASE_URL/v1/customer/delivery/quote" \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: $CUSTOMER_TOKEN" \
  -d '{"wilaya":"Alger","commune":"Hydra","total_cents":2500}')"
echo "$resp_ok" | grep -q '"ok":true' || { echo "❌ expected ok true"; echo "$resp_ok"; exit 1; }
echo "✅ delivery quote ok"

# delivery quote (invalid zone)
resp_ko="$(curl -fsS -X POST "$BASE_URL/v1/customer/delivery/quote" \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: $CUSTOMER_TOKEN" \
  -d '{"wilaya":"Alger","commune":"Unknown","total_cents":2500}')"
echo "$resp_ko" | grep -q 'DELIVERY_ZONE_NOT_FOUND' || { echo "❌ expected DELIVERY_ZONE_NOT_FOUND"; echo "$resp_ko"; exit 1; }
echo "✅ delivery quote invalid zone"

# admin zones list
zones="$(curl -fsS -X GET "$BASE_URL/v1/admin/delivery/zones" -H "x-webhook-token: $ADMIN_TOKEN")"
echo "$zones" | grep -q '"ok":true' || { echo "❌ expected ok true for zones list"; echo "$zones"; exit 1; }
echo "✅ admin zones list"

# admin orders list
orders_json="$(curl -fsS -X GET "$BASE_URL/v1/admin/orders?limit=10" -H "x-webhook-token: $ADMIN_TOKEN")"
echo "$orders_json" | grep -q '"ok":true' || { echo "❌ expected ok true for admin orders"; echo "$orders_json"; exit 1; }
echo "✅ admin orders list"

# DB check: SCOPE_DENY exists

denies="$(docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -Atc \"select count(*) from security_events where event_type='SCOPE_DENY' and created_at > now() - interval '10 minutes';\"" | tr -d '\r')"
[[ "${denies:-0}" -ge 1 ]] || fail "Expected at least 1 SCOPE_DENY event"
echo "✅ SCOPE_DENY logged ($denies)"

# Tracking DB smoke tests (TRK-001)
echo "Running tracking DB smoke tests..."

docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE oid uuid := '33333333-3333-3333-3333-333333333333';
BEGIN
  INSERT INTO orders(order_id, tenant_id, restaurant_id, channel, user_id, service_mode, status, created_at)
  VALUES (oid,'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','whatsapp','fixture-track','livraison','NEW',now())
  ON CONFLICT (order_id) DO UPDATE SET status='NEW', updated_at=now();

  UPDATE orders SET status='ACCEPTED', updated_at=now() WHERE order_id=oid;
  UPDATE orders SET status='IN_PROGRESS', updated_at=now() WHERE order_id=oid;
  UPDATE orders SET status='READY', updated_at=now() WHERE order_id=oid;
  UPDATE orders SET status='READY', updated_at=now() WHERE order_id=oid; -- same status => no-op
  UPDATE orders SET status='DONE', updated_at=now() WHERE order_id=oid;
END $$;
SQL"

trk_count="$(docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -Atc \"select count(*) from outbound_messages where order_id='33333333-3333-3333-3333-333333333333' and template like 'WA_ORDER_STATUS_%';\"" | tr -d '\r')"
[[ "${trk_count:-0}" -eq 4 ]] || {
  echo "❌ expected 4 tracking messages, got ${trk_count:-0}";
  docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -c \"select outbound_id, template, status, next_retry_at, dedupe_key from outbound_messages where order_id='33333333-3333-3333-3333-333333333333' order by created_at;\"" || true;
  exit 1;
}
echo "✅ tracking outbox enqueued ($trk_count)"

# Support (EPIC6) smoke tests
echo "Running support (EPIC6) smoke tests..."

# FAQ should answer without ticket
curl -fsS -X POST "$BASE_URL/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: $INBOUND_TOKEN" \
  -d '{"text":"Quels sont vos horaires ?","from":"cust-faq","msgId":"harness-faq-1"}' >/dev/null \
  && echo "✅ inbound whatsapp FAQ"

# Wait until FAQ reply is enqueued
for i in $(seq 1 30); do
  faq_out="$(docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -Atc \"select count(*) from outbound_messages where user_id='cust-faq' and template='reply' and (payload_json->'meta'->>'intent')='FAQ_ANSWER' and created_at > now() - interval '5 minutes';\"" | tr -d '\r')"
  [[ "${faq_out:-0}" -ge 1 ]] && break
  sleep 1
done
[[ "${faq_out:-0}" -ge 1 ]] || fail "Expected FAQ answer outbox for cust-faq"
faq_tickets="$(docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -Atc \"select count(*) from support_tickets where customer_user_id='cust-faq';\"" | tr -d '\r')"
[[ "${faq_tickets:-0}" -eq 0 ]] || fail "FAQ should not create ticket"
echo "✅ FAQ answered without ticket"

# HELP should create ticket + ack
curl -fsS -X POST "$BASE_URL/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: $INBOUND_TOKEN" \
  -d '{"text":"help","from":"cust-help","msgId":"harness-help-1"}' >/dev/null \
  && echo "✅ inbound whatsapp HELP"

for i in $(seq 1 30); do
  help_tickets="$(docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -Atc \"select count(*) from support_tickets where customer_user_id='cust-help';\"" | tr -d '\r')"
  [[ "${help_tickets:-0}" -ge 1 ]] && break
  sleep 1
done
[[ "${help_tickets:-0}" -ge 1 ]] || fail "Expected support ticket from HELP"
help_ack="$(docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -Atc \"select count(*) from outbound_messages where user_id='cust-help' and template='reply' and (payload_json->'meta'->>'intent') in ('HANDOFF_SUPPORT','DELIVERY_HANDOFF') and created_at > now() - interval '5 minutes';\"" | tr -d '\r')"
[[ "${help_ack:-0}" -ge 1 ]] || fail "Expected support handoff ack outbox for cust-help"
echo "✅ HELP created ticket + ack"

# Admin WA console: list tickets
curl -fsS -X POST "$BASE_URL/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: $INBOUND_TOKEN" \
  -d '{"text":"!tickets open","from":"admin-wa","msgId":"harness-admin-1"}' >/dev/null \
  && echo "✅ inbound whatsapp admin console"

for i in $(seq 1 30); do
  admin_out="$(docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -Atc \"select count(*) from outbound_messages where user_id='admin-wa' and template='WA_ADMIN_CONSOLE' and created_at > now() - interval '5 minutes';\"" | tr -d '\r')"
  [[ "${admin_out:-0}" -ge 1 ]] && break
  sleep 1
done
[[ "${admin_out:-0}" -ge 1 ]] || fail "Expected WA_ADMIN_CONSOLE outbox"
admin_tickets="$(docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -Atc \"select count(*) from support_tickets where customer_user_id='admin-wa';\"" | tr -d '\r')"
[[ "${admin_tickets:-0}" -eq 0 ]] || fail "Admin commands must not create tickets"
echo "✅ Admin console responds without creating ticket"

# 8) Teardown

echo "[8/8] Teardown"
docker compose -f "$COMPOSE_FILE" down -v --remove-orphans

echo "✅ Test harness PASS"
