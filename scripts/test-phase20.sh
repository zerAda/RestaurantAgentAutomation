#!/usr/bin/env bash
# scripts/test-phase20.sh — Phase 20 local harness (docker-free, < 5s)
#
# Runs the pure decision-seam node --test + the classifier node --test (when
# present, added by 20-03) + jq STRUCTURAL checks on W0_MODULE_GUARD.json (incl.
# the graph-reachability "0 Strapi on hit" proof) + an OPTIONAL ephemeral
# redis-server SET->GET round-trip on the canonical key. Mirrors scripts/test-redis.sh
# (the local redis-cli mechanism) and the 20-VALIDATION.md no-docker / Node-22 setup.
#
# Usage: bash scripts/test-phase20.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT_DIR"

NODE="${NODE:-/opt/node22/bin/node}"
GUARD="workflows/W0_MODULE_GUARD.json"
SEAM_TEST="scripts/guard/__tests__/entitlement-decision.test.mjs"
CLASSIFY_TEST="scripts/guard/__tests__/classify-deny.test.mjs"
REDIS_PORT="${PHASE20_REDIS_PORT:-7390}"
CANONICAL_KEY="ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp"

fail() { echo "❌ FAIL: $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

REDIS_PID=""
cleanup() {
  if [[ -n "${REDIS_PID}" ]]; then
    redis-cli -p "${REDIS_PORT}" shutdown nosave >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "== Phase 20 harness (docker-free) =="
command -v "$NODE" >/dev/null 2>&1 || fail "Node 22 not found at $NODE"
"$NODE" --version

# ---------------------------------------------------------------------------
echo ""
echo "[1] Decision-seam node --test"
"$NODE" --test "$SEAM_TEST" || fail "entitlement-decision node --test red"
pass "decision seam green"

# Classifier test is added by 20-03 — run it if present.
if [[ -f "$CLASSIFY_TEST" ]]; then
  echo ""
  echo "[1b] Classifier node --test"
  "$NODE" --test "$CLASSIFY_TEST" || fail "classify-deny node --test red"
  pass "classifier green"
fi

# ---------------------------------------------------------------------------
echo ""
echo "[2] jq structural checks on $GUARD"
python3 -c "import json; json.load(open('$GUARD'))" || fail "guard JSON invalid"

jq -e '[.nodes[]|select(.type=="n8n-nodes-base.redis")]|length>=2' "$GUARD" >/dev/null \
  || fail "<2 Redis nodes"
jq -e '[.nodes[]|select(.type=="n8n-nodes-base.redis")|select(.parameters.operation=="get")|select(.parameters.key|test("ralphe:entitlement:"))]|length>=1' "$GUARD" >/dev/null \
  || fail "Redis GET not keyed ralphe:entitlement:"
jq -e '[.nodes[]|select(.type=="n8n-nodes-base.redis")|select(.parameters.operation=="set")|select(.parameters.key|test("ralphe:entitlement:"))|select(.parameters.ttl!=null)]|length>=1' "$GUARD" >/dev/null \
  || fail "Redis SET not keyed ralphe:entitlement: with a ttl"
jq -e '[.nodes[]|select(.type=="n8n-nodes-base.httpRequest")]|length==2' "$GUARD" >/dev/null \
  || fail "expected exactly 2 Strapi httpRequest nodes"
jq -e '[.nodes[]|select(.type=="n8n-nodes-base.httpRequest")|select(.parameters.url|test("product-modules"))]|length>=1' "$GUARD" >/dev/null \
  || fail "product-modules fetch missing"
jq -e '[.nodes[]|select(.type=="n8n-nodes-base.httpRequest")|select(.parameters.url|test("tenant-entitlements"))]|length>=1' "$GUARD" >/dev/null \
  || fail "tenant-entitlements fetch missing"
grep -q "GUARD_ERROR_FAILCLOSED" "$GUARD" || fail "fail-closed reason missing"
grep -q "ENTITLEMENT_CACHE_TTL_SEC" "$GUARD" || fail "positive TTL env not read"
grep -q "ENTITLEMENT_NEG_CACHE_TTL_SEC" "$GUARD" || fail "negative TTL env not read"
if grep -qiE "NODE_FUNCTION_ALLOW_EXTERNAL|require\\('ioredis'\\)|require\\(\"ioredis\"\\)|\\.scan\\(|KEYS " "$GUARD"; then
  fail "forbidden ioredis/SCAN/KEYS/NODE_FUNCTION_ALLOW_EXTERNAL pattern"
fi
pass "Redis GET/SET keyed, 2 Strapi httpRequest, TTLs, fail-closed, no ioredis/SCAN"

# Graph-reachability: ZERO httpRequest nodes reachable from the IF HIT branch (main[0]).
jq -e '
  (reduce .nodes[] as $n ({}; .[$n.name] = $n.type)) as $types |
  .connections as $conn |
  ($conn["IF - Cache Usable?"].main[0] | map(.node)) as $seed |
  (reduce range(0;50) as $i ($seed;
     . + ([.[] | $conn[.].main // [] | .[] | .[] | .node]) | unique)) as $reachable |
  ([$reachable[] | select($types[.]=="n8n-nodes-base.httpRequest")] | length) == 0
' "$GUARD" >/dev/null || fail "httpRequest reachable on HIT path (0 Strapi round-trips on hit violated)"
pass "graph-reachability: 0 Strapi httpRequest reachable on HIT path"

# ---------------------------------------------------------------------------
echo ""
echo "[3] Optional ephemeral-redis round-trip on the canonical key"
if command -v redis-server >/dev/null 2>&1 && command -v redis-cli >/dev/null 2>&1; then
  redis-server --port "${REDIS_PORT}" --daemonize yes --save "" --appendonly no --dir /tmp >/dev/null 2>&1
  REDIS_PID="started"
  # wait for readiness
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if redis-cli -p "${REDIS_PORT}" ping 2>/dev/null | grep -q PONG; then break; fi
    sleep 0.1
  done
  redis-cli -p "${REDIS_PORT}" set "${CANONICAL_KEY}" \
    '{"ent":{"enabled":true},"mod":{"tier":"addon"},"fetchedAt":"x"}' EX 300 >/dev/null \
    || fail "ephemeral redis SET failed"
  VAL="$(redis-cli -p "${REDIS_PORT}" get "${CANONICAL_KEY}")"
  [[ -n "$VAL" && "$VAL" != "nil" ]] || fail "ephemeral redis GET returned nil on the canonical key"
  redis-cli -p "${REDIS_PORT}" shutdown nosave >/dev/null 2>&1 || true
  REDIS_PID=""
  pass "ephemeral redis SET->GET round-trip on ${CANONICAL_KEY}"
else
  echo "ℹ️  redis-server/redis-cli absent — skipping the live round-trip (structural checks still ran)"
fi

echo ""
echo "✅ Phase 20 harness PASS"
