#!/usr/bin/env bash
set -euo pipefail

: "${DOMAIN_NAME:?missing}"

API="https://api.${DOMAIN_NAME}"
TOKEN="${SMOKE_TOKEN:-${WEBHOOK_SHARED_TOKEN:-}}"

echo "== Smoke tests =="

curl -fsS "${API}/healthz" >/dev/null && echo "✅ healthz"

if [[ -z "$TOKEN" ]]; then
  echo "⚠️  No SMOKE_TOKEN/WEBHOOK_SHARED_TOKEN set. Skipping inbound auth smoke."
  exit 0
fi

echo "== Inbound valid token =="
curl -fsS -X POST "${API}/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: ${TOKEN}" \
  -d '{"text":"test","from":"smoke","msgId":"smoke-1"}' >/dev/null \
  && echo "✅ inbound whatsapp (valid token)"


echo "== Inbound v2 contract (valid) =="
curl -fsS -X POST "${API}/v1/inbound/instagram"   -H "Content-Type: application/json"   -H "x-webhook-token: ${TOKEN}"   -H "x-contract-version: v2"   -d '{"contract_version":"v2","provider":"ig","msg_id":"smoke-v2-1","sender":{"id":"ig-smoke"},"message":{"text":"hello v2"},"timestamp":"2026-01-22T10:00:00Z"}' >/dev/null   && echo "✅ inbound instagram v2 (valid token + v2)"

echo "== Inbound v2 contract (invalid payload should 400) =="
status="$(curl -s -o /tmp/smoke_invalid.json -w "%{http_code}" -X POST "${API}/v1/inbound/instagram"   -H "Content-Type: application/json"   -H "x-webhook-token: ${TOKEN}"   -H "x-contract-version: v2"   -d '{"contract_version":"v2","provider":"ig","msg_id":"smoke-v2-bad","message":{"text":"missing sender"},"timestamp":"2026-01-22T10:00:00Z"}')"
if [[ "$status" != "400" ]]; then
  echo "❌ expected 400, got $status. Body:"
  cat /tmp/smoke_invalid.json || true
  exit 1
fi
echo "✅ inbound instagram v2 invalid -> 400"

echo "== Inbound invalid token (should be dropped + logged) =="
curl -fsS -X POST "${API}/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: invalid-token" \
  -d '{"text":"test","from":"smoke","msgId":"smoke-2"}' >/dev/null \
  && echo "✅ inbound whatsapp (invalid token sent; expect AUTH_DENY in DB)"

echo "== SSRF audioUrl blocked (should be logged) =="
curl -fsS -X POST "${API}/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: ${TOKEN}" \
  -d '{"audioUrl":"http://127.0.0.1/evil.ogg","from":"smoke","msgId":"smoke-3"}' >/dev/null \
  && echo "✅ inbound whatsapp (audioUrl sent; expect AUDIO_URL_BLOCKED in DB)"

echo "== Optional: query token auth (should be denied if ALLOW_QUERY_TOKEN=false) =="
if [[ "${SMOKE_TEST_QUERY_TOKEN:-0}" == "1" ]]; then
  curl -fsS -X POST "${API}/v1/inbound/whatsapp?token=${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"text":"test","from":"smoke","msgId":"smoke-4"}' >/dev/null \
    && echo "✅ inbound whatsapp (token in query sent; expect AUTH_DENY unless ALLOW_QUERY_TOKEN=true)"
fi

echo "== DB checks (optional) =="
if command -v docker >/dev/null 2>&1; then
  set +e
  docker compose -f docker-compose.hostinger.prod.yml exec -T postgres sh -lc \
    "psql -U n8n -d n8n -Atc \"SELECT event_type||':'||COUNT(*) FROM security_events WHERE created_at > now() - interval '10 minutes' GROUP BY event_type ORDER BY COUNT(*) DESC;\"" \
    && echo "✅ security_events aggregated (last 10 min)"
  set -e
else
  echo "ℹ️  docker not found: skipping DB checks"
fi

echo "Done."
