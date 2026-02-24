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

# Wait for postgres

echo "Waiting for postgres..."
for i in $(seq 1 60); do
  if docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "pg_isready -U n8n -d n8n" >/dev/null 2>&1; then
    break
  fi
  sleep 1
  if [[ $i -eq 60 ]]; then fail "postgres not ready"; fi
 done

# 2) Apply migrations

echo "[2/8] Apply migrations"
for m in $(ls -1 db/migrations/*.sql 2>/dev/null | sort); do
  echo "- $m"
  COMPOSE_FILE="$COMPOSE_FILE" ./scripts/db_migrate.sh "$COMPOSE_FILE" "$m"
done

# 3) Seed fixtures

echo "[3/8] Seed fixtures"
for f in $(ls -1 tests/fixtures/*.sql 2>/dev/null | sort); do
  echo "- $f"
  docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -v ON_ERROR_STOP=1 -U n8n -d n8n < /dev/stdin" < "$f"
done

# 4) Start n8n (CORE_WORKFLOW_ID is injected after import)

echo "[4/8] Up: n8n (initial)"
CORE_WORKFLOW_ID="" docker compose -f "$COMPOSE_FILE" up -d n8n

# Wait n8n port open (best-effort)

echo "Waiting for n8n to start..."
for i in $(seq 1 60); do
  if curl -fsS "http://localhost:25678/" >/dev/null 2>&1; then
    break
  fi
  sleep 2
  if [[ $i -eq 60 ]]; then fail "n8n did not start"; fi
done

# 5) Import workflows
# Note: Webhook triggers must be active to receive requests.

echo "[5/8] Import workflows"
# Import CORE first

docker compose -f "$COMPOSE_FILE" exec -T n8n sh -lc "n8n import:workflow --input=/opt/resto/workflows/W4_CORE.json" || fail "import CORE failed"

# Import ADMIN WA Support Console (W14) (required for admin WhatsApp piloting)
docker compose -f "$COMPOSE_FILE" exec -T n8n sh -lc "n8n import:workflow --input=/opt/resto/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json" || fail "import W14 admin WA console failed"

# Get core ID
core_id="$(docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -Atc \"select id from workflow_entity where name='W4 - CORE Agent (State + Voice + Secure)' order by id desc limit 1;\"" | tr -d '\r')"
[[ -n "$core_id" ]] || fail "CORE workflow ID not found after import"

# Get W14 ID
admin_wa_id="$(docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -Atc \"select id from workflow_entity where name='W14 - ADMIN WA Support Console' order by id desc limit 1;\"" | tr -d '\r')"
[[ -n "$admin_wa_id" ]] || fail "W14 workflow ID not found after import"

# Recreate n8n with CORE_WORKFLOW_ID set

echo "Recreating n8n with CORE_WORKFLOW_ID=$core_id and ADMIN_WA_CONSOLE_WORKFLOW_ID=$admin_wa_id"
docker compose -f "$COMPOSE_FILE" stop n8n
CORE_WORKFLOW_ID="$core_id" ADMIN_WA_CONSOLE_WORKFLOW_ID="$admin_wa_id" docker compose -f "$COMPOSE_FILE" up -d --force-recreate n8n

# Import remaining workflows
for wf in W1_IN_WA.json W2_IN_IG.json W3_IN_MSG.json W8_OPS.json; do
  docker compose -f "$COMPOSE_FILE" exec -T n8n sh -lc "n8n import:workflow --input=/opt/resto/workflows/$wf" || fail "import $wf failed"
done

# Admin workflows
docker compose -f "$COMPOSE_FILE" exec -T n8n sh -lc "n8n import:workflow --input=/opt/resto/workflows/W9_ADMIN_PING.json" || fail "import W9 admin failed"
docker compose -f "$COMPOSE_FILE" exec -T n8n sh -lc "n8n import:workflow --input=/opt/resto/workflows/W11_ADMIN_DELIVERY_ZONES.json" || fail "import W11 admin zones failed"
docker compose -f "$COMPOSE_FILE" exec -T n8n sh -lc "n8n import:workflow --input=/opt/resto/workflows/W12_ADMIN_ORDERS.json" || fail "import W12 admin orders failed"

# Customer workflows
docker compose -f "$COMPOSE_FILE" exec -T n8n sh -lc "n8n import:workflow --input=/opt/resto/workflows/W10_CUSTOMER_DELIVERY_QUOTE.json" || fail "import W10 customer quote failed"

# Activate needed workflows

echo "Activating webhook workflows..."
docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -v ON_ERROR_STOP=1 -c \"update workflow_entity set active=true where name in ('W1 - INBOUND WhatsApp (Safe Parse + Auth + Idempotency)','W2 - INBOUND Instagram (Safe Parse + Auth + Idempotency)','W3 - INBOUND Messenger (Safe Parse + Auth + Idempotency)','W9 - ADMIN Ping (Scopes Enforced)');\"" >/dev/null

# Internal workflows used via ExecuteWorkflow
docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -v ON_ERROR_STOP=1 -c \"update workflow_entity set active=true where name in ('W14 - ADMIN WA Support Console');\"" >/dev/null

# Activate new endpoints
docker compose -f "$COMPOSE_FILE" exec -T postgres sh -lc "psql -U n8n -d n8n -v ON_ERROR_STOP=1 -c \"update workflow_entity set active=true where name in ('W10 - CUSTOMER Delivery Quote (Zone + Fee + ETA)','W11 - ADMIN Delivery Zones (CRUD)','W12 - ADMIN Orders (List + Timeline)');\"" >/dev/null

# 6) Up: gateway

echo "[6/8] Up: gateway"
docker compose -f "$COMPOSE_FILE" up -d gateway

# Wait gateway health

echo "Waiting for gateway /healthz..."
for i in $(seq 1 60); do
  if curl -fsS "$BASE_URL/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 1
  if [[ $i -eq 60 ]]; then fail "gateway not ready"; fi
done

# 7) Smoke tests

echo "[7/8] Smoke tests"

curl -fsS "$BASE_URL/healthz" >/dev/null && echo "✅ healthz"

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
