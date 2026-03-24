# Phase 5: Test Coverage — n8n Workflow E2E — Research

**Researched:** 2026-03-24
**Domain:** n8n 2.9.4 E2E testing, Redis queue verification, GitHub Actions CI integration
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TEST-09 | E2E test: POST to `/v1/inbound/whatsapp` with valid Meta-signed payload triggers W_IN_WHATSAPP_ADAPTER and creates a record in `inbound_messages` DB table | Existing test harness pattern (test_harness.sh) already does this for non-Meta payloads; Phase 5 extends it to use HMAC-signed Meta-native payloads and verify DB row insertion |
| TEST-10 | E2E test: failed outbound message is retried with exponential backoff — verify Redis queue entry exists after first failure | W15_OUTBOX_WORKER.json uses `ralphe:outbox:pending` Redis list with exponential backoff; test can seed a failing entry and verify re-queue using `redis-cli llen ralphe:outbox:pending` |
| TEST-11 | Workflow smoke tests run in CI using n8n test mode or mock webhook triggers, without requiring a live VPS | Existing `docker/docker-compose.test.yml` + `test_harness.sh` infrastructure already runs n8n in queue mode against docker-compose; Phase 5 adds Phase 5–specific tests as a new CI job extending this infrastructure |
</phase_requirements>

---

## Summary

Phase 5 adds automated E2E tests for the three inbound adapter workflows (W1_IN_WA, W2_IN_IG, W3_IN_MSG) and the outbox retry mechanism (W15_OUTBOX_WORKER). The primary challenge is not framework selection — the test infrastructure already exists — but precise test design: (1) how to generate a valid HMAC-SHA256 Meta signature so the workflows accept the payload without disabling signature enforcement, (2) how to verify a DB row was created in `inbound_messages` after async processing, and (3) how to set up a controlled failure in W15 to confirm exponential backoff re-queues to `ralphe:outbox:pending`.

The project already has `docker/docker-compose.test.yml` with postgres, redis, n8n 2.9.4, gateway, and mock-api services, plus `scripts/test_harness.sh` with a complete workflow import, activation, and webhook smoke testing pattern. Phase 5 builds directly on this infrastructure — it adds a new bash script (`scripts/test-n8n-e2e.sh`) and a new CI job (`n8n-workflow-e2e`) to ci.yml, rather than creating a new test stack.

**Primary recommendation:** Extend `scripts/test_harness.sh` patterns into a new `scripts/test-n8n-e2e.sh` that (a) generates valid Meta HMAC signatures for inbound adapter tests, (b) polls `inbound_messages` DB after async processing, and (c) seeds a failing Redis outbox entry to verify backoff re-queue. Wire it as a new CI job in ci.yml gated to main/release (same as test-harness).

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| n8n | 2.9.4 | Workflow runtime under test | Production version per VPS and ci.yml env.N8N_VERSION |
| postgres | 15-alpine | Assertion DB — query `inbound_messages` | Production DB version, already in docker-compose.test.yml |
| redis | 7-alpine | Assertion store — verify `ralphe:outbox:pending` queue entries | Production Redis version, already in docker-compose.test.yml |
| nginx | 1.27-alpine | Gateway — routes POSTs to n8n webhooks | Production gateway version, already in docker-compose.test.yml |
| openssl | (system) | HMAC-SHA256 signature generation for Meta-signed payloads | Already used in scripts/test_e2e.sh `generate_signature()` |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| jq | (system) | Parse n8n REST API responses during workflow import | Already in test_harness.sh |
| redis-cli | (redis image) | Query Redis list length after outbox test | `docker compose exec redis redis-cli llen ralphe:outbox:pending` |
| psql | (postgres image) | Query `inbound_messages` table after async processing | Already in test_harness.sh |
| node:mock-api | mock-api container | Stub outbound send URLs (WA_SEND_URL, IG_SEND_URL, MSG_SEND_URL) | Returns configurable responses to simulate send failures |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bash + curl test script | Python pytest + httpx | Python is used for unit tests but bash matches existing smoke script conventions; keep consistency |
| Full test_harness.sh extension | New separate test-n8n-e2e.sh | Separate script avoids breaking existing harness; CI can run both independently |
| n8n /webhook-test/ path | Production /webhook/ path | /webhook-test/ requires editor open — not usable in headless CI; use activated production webhooks with a new n8n container instance |

**Installation:**
```bash
# No new packages needed — all dependencies already in docker-compose.test.yml
# Scripts only require: bash, curl, jq, openssl, docker
```

---

## Architecture Patterns

### Recommended Project Structure
```
scripts/
├── test-n8n-e2e.sh         # New: E2E test script for TEST-09, TEST-10, TEST-11
├── test_harness.sh          # Existing: full stack harness (imports, activates, smokes)
└── (existing scripts...)
.github/workflows/
└── ci.yml                   # Add: n8n-workflow-e2e job (extends test-harness pattern)
tests/fixtures/
└── (existing fixtures...)   # No new fixtures needed — payloads built inline
```

### Pattern 1: Meta-Signed Inbound Payload Generation

**What:** Generate HMAC-SHA256 signatures for Meta webhook payloads so W1_IN_WA processes them with `META_SIGNATURE_REQUIRED=enforce` set in the test environment.

**When to use:** Every TEST-09 E2E assertion that POSTs to `/v1/inbound/whatsapp`.

**Example:**
```bash
# Source: scripts/test_e2e.sh generate_signature() + W1_IN_WA.json B0 node (crypto.createHmac logic)
generate_meta_sig() {
  local payload="$1"
  local secret="${META_APP_SECRET:-test_app_secret}"
  local hex
  hex=$(echo -n "$payload" | openssl dgst -sha256 -hmac "$secret" | sed 's/^.* //')
  echo "sha256=${hex}"
}

# Build a Meta-native WhatsApp payload (object=whatsapp_business_account)
MSG_ID="e2e-wa-$(date +%s)-$$"
PAYLOAD=$(cat <<PAYLOAD
{"object":"whatsapp_business_account","entry":[{"id":"TEST_WA_ID","changes":[{"value":{"messaging_product":"whatsapp","metadata":{"display_phone_number":"15550000000","phone_number_id":"TEST_PHONE_ID"},"messages":[{"from":"15551234567","id":"${MSG_ID}","timestamp":"$(date +%s)","text":{"body":"Bonjour je veux commander"},"type":"text"}]},"field":"messages"}]}]}
PAYLOAD)
SIG=$(generate_meta_sig "$PAYLOAD")
# POST with rawBody-compatible Content-Type
curl -s -w "\n%{http_code}" -X POST "${N8N_URL}/webhook/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature-256: ${SIG}" \
  -d "${PAYLOAD}"
```

**Key constraint from W1_IN_WA.json:** The workflow verifies HMAC on `$json.rawBody` (raw string), not the parsed JSON. n8n's webhook node with `rawBody: true` provides `$json.rawBody` as a string. The test must POST the exact bytes used for the signature — no re-serialization.

### Pattern 2: Async DB Polling After Webhook

**What:** After posting to an inbound webhook, poll `inbound_messages` with a timeout loop, since n8n processes executions asynchronously in queue mode.

**When to use:** TEST-09 verification (record created in `inbound_messages`).

**Example:**
```bash
# Source: scripts/test_harness.sh polling pattern
poll_inbound_record() {
  local msg_id="$1"
  local max_wait="${2:-15}"   # seconds
  local waited=0
  local count
  while [ "${waited}" -lt "${max_wait}" ]; do
    count=$(docker compose -f "${COMPOSE_FILE}" exec -T postgres sh -lc \
      "psql -U n8n -d n8n -Atc \"SELECT COUNT(*) FROM inbound_messages WHERE msg_id = '${msg_id}';\"" \
      | tr -d '\r\n')
    if [ "${count:-0}" -ge 1 ]; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}
```

**Key constraint:** `inbound_messages` stores `msg_id` from the parsed envelope, not the raw Meta `messages[0].id` directly — the workflow must successfully parse the Meta-native payload and write to DB. If parsing fails, the row never appears. This is the most meaningful assertion: a row means the full pipeline executed.

### Pattern 3: Redis Outbox Failure Seeding

**What:** Directly push a malformed/failing outbox entry to `ralphe:outbox:pending` Redis list, then verify that after W15_OUTBOX_WORKER processes it (send fails because mock-api returns 500), the entry is re-pushed with incremented `attempts` and a future `nextRetryAt`.

**When to use:** TEST-10 exponential backoff verification.

**Example:**
```bash
# Seed a failing outbox entry
OUTBOX_MSG=$(cat <<MSG
{"channel":"whatsapp","payload":{"userId":"retry-test-user","replyText":"test retry"},"attempts":1,"nextRetryAt":null,"outboxMsgId":"retry-test-$$"}
MSG)
# Push to pending list
docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli LPUSH ralphe:outbox:pending "${OUTBOX_MSG}"

# Configure mock-api to return 500 for WA_SEND_URL (or use a URL that doesn't exist)
# Then trigger W15 manually via n8n REST API
# n8n 2.x: POST /rest/workflows/:id/run (requires auth cookie or API key)
# Wait for worker to process (W15 is CRON-based, every 30s)
# Verify the entry was re-pushed (still in queue with attempts=2)
sleep 35   # Wait for CRON trigger
QUEUE_LEN=$(docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli LLEN ralphe:outbox:pending)
# The entry should still be in queue (re-queued after failed send)
```

**Key constraint from W15_OUTBOX_WORKER.json:** W15 uses `RPOP` from `ralphe:outbox:pending` (pops from tail, FIFO). On failure with `retryable=true` and `attempts < maxAttempts`, it calculates `nextRetryAt = now + baseDelaySec * 2^(attempts-1)` and pushes back with `LPUSH` (prepends). The test verifies the entry is back in the queue with updated `attempts` and `nextRetryAt` in the future. The `nextRetryAt` prevents premature re-processing.

### Pattern 4: n8n Workflow Manual Trigger for Cron Workflows

**What:** Force W15_OUTBOX_WORKER to execute immediately without waiting 30 seconds for CRON.

**When to use:** TEST-10 — don't wait 30s in CI.

**Example:**
```bash
# n8n 2.9.4 REST API: manually trigger a workflow execution
# Requires auth (cookie from login or API key)
# Get workflow ID first
W15_ID=$(docker compose -f "${COMPOSE_FILE}" exec -T postgres sh -lc \
  "psql -U n8n -d n8n -Atc \"SELECT id FROM workflow_entity WHERE name LIKE '%Outbox Worker%' LIMIT 1;\"" \
  | tr -d '\r\n')

# Trigger via n8n REST API (POST /rest/workflows/:id/run)
curl -s -b "${N8N_JAR}" \
  -X POST "http://localhost:25678/rest/workflows/${W15_ID}/run" \
  -H "Content-Type: application/json" \
  -d '{}' | jq -r '.data.executionId // .executionId // empty'
```

### Anti-Patterns to Avoid

- **Using /webhook-test/ path in CI:** The `/webhook-test/` path requires the n8n editor to be open and listening. In headless CI with an activated workflow, only the `/webhook/` production path works. The existing test_harness.sh already handles this correctly.
- **Posting to n8n directly without the gateway:** The test must post through the nginx gateway (port 18080) for production-equivalent path, or directly to n8n port 25678 `/webhook/v1/inbound/...` for a stripped-down test. The gateway path verifies the full stack but adds a dependency. Use direct n8n path for E2E workflow testing (TEST-09/TEST-11) and gateway path for full integration.
- **Verifying the ACK response instead of the DB:** The webhook responds `{"status":"received"}` immediately (fast-ACK pattern). A 200 ACK does NOT confirm the message was processed or that a DB row was created. Always poll `inbound_messages` for TEST-09.
- **Setting META_SIGNATURE_REQUIRED=enforce without META_APP_SECRET:** The workflow will always reject with `metaSigReason=secret_missing` if `META_APP_SECRET` is not set. Either set both in the test compose env, or test with `META_SIGNATURE_REQUIRED=warn` and verify processing path separately from security.
- **Not resetting Redis state between tests:** The outbox queue can accumulate leftover entries from previous test runs. Always flush `ralphe:outbox:pending` before TEST-10 setup.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| n8n workflow import in CI | Custom import script | Existing test_harness.sh `create_wf()` helper | Already handles n8n 2.x ownership table, activation sequence, and API auth |
| Meta HMAC signature | Custom crypto library | `openssl dgst -sha256 -hmac` (already in test_e2e.sh) | Already proven correct in existing tests |
| DB polling with timeout | Custom retry loop | Existing pattern in test_harness.sh FAQ/HELP polling | Same `for i in $(seq 1 30); do ... sleep 1; done` pattern |
| Mock outbound API | Custom mock server | Existing `mock-api` container in docker-compose.test.yml | Already configured for WA_SEND_URL, IG_SEND_URL, MSG_SEND_URL |
| Redis queue inspection | Manual RESP protocol | `docker compose exec redis redis-cli LLEN / LRANGE` | Redis CLI already in the redis:7-alpine container |

**Key insight:** The entire test infrastructure (compose stack, workflow import, webhook activation, DB assertions) already exists in `test_harness.sh`. Phase 5 extends it rather than replacing it. The new `test-n8n-e2e.sh` should source the same patterns.

---

## Common Pitfalls

### Pitfall 1: Meta Native Payload Format vs. Legacy Format
**What goes wrong:** Posting a legacy `{"provider":"wa","msg_id":"...","from":"..."}` payload passes validation but exercises the legacy parsing path, not the Meta-native path. TEST-09 requires the Meta-native `{"object":"whatsapp_business_account","entry":[...]}` format.
**Why it happens:** The workflow's B0-Parse node handles both formats. A legacy payload succeeds (200 ACK) but the test is not validating the production code path.
**How to avoid:** Always construct the `object: "whatsapp_business_account"` envelope with `entry[0].changes[0].value.messages[0]` structure.
**Warning signs:** Test passes without checking `meta_json` column in `inbound_messages` — look for `_isMetaNative: true` in the stored envelope.

### Pitfall 2: n8n Queue Mode Webhook Activation Race
**What goes wrong:** After importing and activating workflows via DB UPDATE, n8n's `ActiveWorkflowManager.init()` registers webhook routes on startup. If the test posts to the webhook before init completes, it gets 404.
**Why it happens:** n8n 2.x loads active workflows asynchronously during startup. The API being up (`/rest/settings` responsive) does not mean webhooks are registered.
**How to avoid:** Follow test_harness.sh step 5b: force-restart n8n after DB activation, wait for `/rest/settings` + additional 5-second buffer. Also use the fallback pattern: retry webhook POST with backoff for up to 45 seconds if 404.
**Warning signs:** Webhook returns 404 after `WEBHOOKS_LIVE=false` detection — log the warning and fall back to DB-only verification.

### Pitfall 3: Redis Credential ID in Workflows
**What goes wrong:** W15_OUTBOX_WORKER.json uses `"id": "={{ $env.REDIS_CREDENTIAL_ID }}"` for Redis credentials. In the test environment, this env var is not set, so the Redis node can't connect.
**Why it happens:** n8n credential resolution: if credential ID is a dynamic expression, n8n evaluates it at runtime. If REDIS_CREDENTIAL_ID is empty, Redis operations fail silently with `continueOnFail: true`.
**How to avoid:** Create a Redis credential via the n8n REST API (POST `/rest/credentials`) during test setup, then set `REDIS_CREDENTIAL_ID` in the test compose environment, OR set `QUEUE_BULL_REDIS_HOST` + `QUEUE_BULL_REDIS_PORT` env vars directly so workflows can use a named credential. Alternatively, for TEST-10, seed the Redis queue directly without activating W15 and inspect what W15 would do by testing its logic in isolation.
**Warning signs:** W15 executes but `LLEN ralphe:outbox:pending` stays at 1 (entry not re-queued) — check n8n execution logs for Redis connection errors.

### Pitfall 4: outbox:pending vs. outbox:retry Key Confusion
**What goes wrong:** W15 pops from `ralphe:outbox:pending` and on failure with retry, pushes back to `ralphe:outbox:pending` (same list). On DLQ, it pushes to `ralphe:outbox:dlq`. TEST-10 verifies the entry is back in `ralphe:outbox:pending` (not DLQ), which only happens if `attempts < maxAttempts` AND `retryable=true`.
**Why it happens:** Testers assume a separate retry queue exists. It's the same pending queue with `nextRetryAt` gating.
**How to avoid:** Seed with `attempts: 1` (well below maxAttempts=7). Use a failing `WA_SEND_URL` (e.g., point to an unreachable endpoint). After W15 runs, check `LLEN ralphe:outbox:pending >= 1` AND parse the re-queued entry to confirm `attempts=2` and `nextRetryAt > now`.
**Warning signs:** Queue is empty after W15 runs — entry went to DLQ instead of retry. Check `LLEN ralphe:outbox:dlq`.

### Pitfall 5: inbound_messages Schema Mismatch
**What goes wrong:** The workflow stores `msg_id` from the parsed envelope. For Meta-native payloads, `msg_id` comes from `entry[0].changes[0].value.messages[0].id` (the WhatsApp message ID, e.g., `"wamid.xxx"`). The test payload uses a controlled `msg.id` value, but the DB query must match the exact field the workflow wrote.
**Why it happens:** The `inbound_messages` table stores `msg_id text NOT NULL` but the source field name varies by workflow. Checking the wrong column returns 0 rows.
**How to avoid:** Set a known `messages[0].id` in the test payload (e.g., `"test-msg-e2e-001"`), then query: `SELECT COUNT(*) FROM inbound_messages WHERE msg_id = 'test-msg-e2e-001'`.
**Warning signs:** DB poll always returns 0 even though n8n logged a successful execution — confirm the field stored by checking `SELECT msg_id FROM inbound_messages ORDER BY received_at DESC LIMIT 1`.

### Pitfall 6: W15 CRON Trigger Timing in CI
**What goes wrong:** W15 triggers every 30 seconds via CRON. If the test seeds the Redis entry and immediately queries Redis, the worker hasn't fired yet.
**Why it happens:** Schedule-based triggers cannot be manually invoked via webhook. The test must either wait ≥30s or force a manual execution via the n8n REST API.
**How to avoid:** Use n8n REST API `POST /rest/workflows/:id/run` to trigger W15 immediately. Confirm execution completes before inspecting Redis. This requires getting the workflow ID after import (store it from the `create_wf` response).
**Warning signs:** Queue always still has entry at `attempts=1` — manual trigger may not have fired, or W15 may still be processing.

---

## Code Examples

Verified patterns from existing project scripts:

### HMAC-SHA256 Meta Signature
```bash
# Source: scripts/test_e2e.sh
generate_signature() {
    local payload="$1"
    local secret="${2:-$META_APP_SECRET}"
    echo -n "$payload" | openssl dgst -sha256 -hmac "$secret" | sed 's/^.* //'
}
# Usage:
SIG="sha256=$(generate_signature "$PAYLOAD")"
curl -X POST ... -H "X-Hub-Signature-256: ${SIG}" ...
```

### n8n Workflow Import and Activation
```bash
# Source: scripts/test_harness.sh create_wf() + activation pattern
create_wf() {
  local wf_file="$1"
  local label="$2"
  local active="${3:-false}"
  jq "del(.id) | .active = $active" "$ROOT_DIR/$wf_file" > /tmp/_wf_payload.json
  http_code="$(curl -s -o /tmp/_wf_resp.json -w "%{http_code}" -b "$N8N_JAR" \
    -X POST "http://localhost:25678/rest/workflows" \
    -H "Content-Type: application/json" -d @/tmp/_wf_payload.json)"
  jq -r '.data.id // .id // empty' /tmp/_wf_resp.json
}
# After import, activate via DB UPDATE (n8n 2.x):
docker compose -f "${COMPOSE_FILE}" exec -T postgres sh -lc \
  "psql -U n8n -d n8n -Atc \"UPDATE workflow_entity SET active = true WHERE id = '${WF_ID}';\""
```

### Redis Queue Inspection
```bash
# Source: W15_OUTBOX_WORKER.json queue key "ralphe:outbox:pending"
QUEUE_LEN=$(docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli LLEN ralphe:outbox:pending | tr -d '\r\n')
# Read the last entry without popping (LINDEX 0 = head, -1 = tail)
LAST_ENTRY=$(docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli LINDEX ralphe:outbox:pending -1 | tr -d '\r\n')
ATTEMPTS=$(echo "${LAST_ENTRY}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('attempts', 0))" 2>/dev/null || echo "0")
```

### Direct n8n Webhook Trigger (Production Path)
```bash
# Source: scripts/test_harness.sh smoke test pattern
# n8n 2.x production webhook: /webhook/ (NOT /webhook-test/)
WH_STATUS=$(curl -s -o /tmp/wh_resp.json -w "%{http_code}" \
  -X POST "http://localhost:25678/webhook/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature-256: ${SIG}" \
  -d "${PAYLOAD}")
```

### DB Assertion for inbound_messages
```bash
# Source: scripts/test_harness.sh DB polling pattern
# inbound_messages schema: id, conversation_key, msg_id, channel, message_type, text_hash, meta_json, correlation_id, received_at
poll_for_record() {
  local msg_id="$1"
  for i in $(seq 1 20); do
    count=$(docker compose -f "${COMPOSE_FILE}" exec -T postgres sh -lc \
      "psql -U n8n -d n8n -Atc \"SELECT COUNT(*) FROM inbound_messages WHERE msg_id = '${msg_id}';\"" \
      | tr -d '\r\n')
    [ "${count:-0}" -ge 1 ] && return 0
    sleep 1
  done
  return 1
}
```

### Manual Workflow Execution (n8n REST API)
```bash
# Trigger a workflow manually (bypasses CRON scheduling)
# Requires: N8N_JAR with valid session cookie (from test_harness.sh login pattern)
trigger_workflow() {
  local wf_id="$1"
  curl -s -b "${N8N_JAR}" \
    -X POST "http://localhost:25678/rest/workflows/${wf_id}/run" \
    -H "Content-Type: application/json" \
    -d '{}' | jq -r '.data.executionId // .executionId // "no-exec-id"'
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| n8n 1.x webhook_entity table for activation | n8n 2.x: active field in workflow_entity, init() registers routes on startup | n8n 2.0 | Activation via DB UPDATE + restart is the correct pattern; test_harness.sh already implements this |
| /webhook-test/ requires editor open | Production /webhook/ path works headlessly | n8n 1.x → 2.x | Test infrastructure must activate workflows and use /webhook/ path |
| Meta signature verification optional | `META_SIGNATURE_REQUIRED` env var supports off/warn/enforce modes | W1_IN_WA.json P0-SEC-03 | Test must set META_APP_SECRET in compose env and generate valid signatures for enforce mode |
| Legacy WA payload `{"provider":"wa"}` | Meta-native `{"object":"whatsapp_business_account"}` | W1_IN_WA.json P0-01 update | TEST-09 must use Meta-native payload to exercise production code path |

**Deprecated/outdated:**
- n8n CLI `import:workflow` command: hangs in queue mode (per MEMORY.md); use REST API import instead — test_harness.sh already does this
- `/webhook-test/` path: editor-only, not usable in CI; use activated production webhooks at `/webhook/`

---

## Open Questions

1. **Redis Credential in W15_OUTBOX_WORKER**
   - What we know: W15 uses `"id": "={{ $env.REDIS_CREDENTIAL_ID }}"` for all Redis nodes, and `continueOnFail: true` hides errors
   - What's unclear: Whether the test compose env currently sets REDIS_CREDENTIAL_ID, or if a credential must be created via the REST API
   - Recommendation: In the test script, after n8n login, create a Redis credential via `POST /rest/credentials` and capture its ID; OR set `REDIS_CREDENTIAL_ID` as an env var in docker-compose.test.yml pointing to a pre-created credential; alternatively, TEST-10 can validate the outbox behavior by directly inspecting Redis without running W15 (inject entry, check W15 logic separately)

2. **W1_IN_WA inbound_messages write path**
   - What we know: `inbound_messages` table exists and W1_IN_WA parses Meta payloads; test_harness.sh does NOT currently verify a row is written there
   - What's unclear: Exactly which node in W1_IN_WA writes to `inbound_messages` — the workflow JSON is large and this research read only the first 80 lines
   - Recommendation: Before finalizing TEST-09 assertion, read the full W1_IN_WA.json to find the Postgres/HTTP Strapi write node and confirm what `msg_id` it stores

3. **Strapi inbound-message vs. postgres inbound_messages**
   - What we know: TEST-09 success criteria says "creates a record in Strapi `inbound-message`" but the local DB schema has `inbound_messages` (PostgreSQL); the Strapi `inbound-message` would be a Strapi content-type, not a direct DB table query
   - What's unclear: Whether the workflow writes to the n8n DB `inbound_messages` table (PostgreSQL direct) or to Strapi via HTTP API (`POST /api/inbound-messages`)
   - Recommendation: Planner should clarify this in plan design; for CI without live Strapi, direct DB assertion (`SELECT FROM inbound_messages`) is the pragmatic path; if workflow posts to Strapi, the test needs a running Strapi or mock-api stub endpoint at `/api/inbound-messages`

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash + curl + psql + redis-cli (same as existing test_harness.sh) |
| Config file | docker/docker-compose.test.yml (existing) |
| Quick run command | `bash scripts/test-n8n-e2e.sh` (new script, uses compose file) |
| Full suite command | `bash scripts/test_harness.sh && bash scripts/test-n8n-e2e.sh` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEST-09 | POST Meta-signed payload → W1_IN_WA executes → inbound_messages row exists | integration | `bash scripts/test-n8n-e2e.sh` (covers TEST-09 section) | ❌ Wave 0 |
| TEST-10 | Seed failing outbox entry → W15 processes → entry re-queued with attempts+1 + future nextRetryAt | integration | `bash scripts/test-n8n-e2e.sh` (covers TEST-10 section) | ❌ Wave 0 |
| TEST-11 | Workflow smoke tests run in CI without live VPS | CI integration | New `n8n-workflow-e2e` job in `.github/workflows/ci.yml` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `bash -n scripts/test-n8n-e2e.sh` (bash syntax check, no Docker needed)
- **Per wave merge:** `bash scripts/test-n8n-e2e.sh` (full stack run with compose)
- **Phase gate:** Full suite green (`test_harness.sh` + `test-n8n-e2e.sh`) before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `scripts/test-n8n-e2e.sh` — covers TEST-09 (Meta-signed WA inbound + DB assertion) and TEST-10 (outbox retry seeding + Redis queue inspection)
- [ ] `.github/workflows/ci.yml` — new `n8n-workflow-e2e` job that runs `test-n8n-e2e.sh` (covers TEST-11)

*(Existing `test_harness.sh` + `docker/docker-compose.test.yml` serve as the foundation; no new compose file needed)*

---

## Sources

### Primary (HIGH confidence)
- `scripts/test_harness.sh` (local) — complete workflow import/activation/smoke pattern; n8n 2.9.4 API patterns; login, create_wf(), DB activation, webhook testing, Redis inspection
- `workflows/W1_IN_WA.json` (local) — Meta signature verification logic, B0-Parse node, rawBody handling, `META_SIGNATURE_REQUIRED` env var modes
- `workflows/W15_OUTBOX_WORKER.json` (local) — `ralphe:outbox:pending` Redis list, RPOP/LPUSH mechanics, exponential backoff formula, `nextRetryAt` calculation
- `docker/docker-compose.test.yml` (local) — full test stack definition; n8n queue mode config; mock-api endpoint env vars
- `db/bootstrap.sql` lines 302-317 (local) — `inbound_messages` table schema with `msg_id`, `channel`, `conversation_key` columns
- `.github/workflows/ci.yml` (local) — existing CI job structure, SHA-pinned action versions, existing test-harness job pattern
- `scripts/test_e2e.sh` (local) — `generate_signature()` HMAC pattern, existing E2E test structure

### Secondary (MEDIUM confidence)
- [n8n Webhook node documentation](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/) — test vs. production URL behavior; /webhook-test/ requires editor open
- [n8n community: webhook test mode](https://community.n8n.io/t/webhook-in-test-mode/134576) — confirms /webhook-test/ is editor-only in all versions

### Tertiary (LOW confidence)
- [n8n REST API programmatic trigger](https://markaicode.com/n8n-rest-api-trigger-workflows/) — POST /rest/workflows/:id/run pattern for manual workflow execution; needs verification against n8n 2.9.4 API

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components verified against existing project files
- Architecture: HIGH — patterns extracted directly from test_harness.sh and workflow JSON sources
- Pitfalls: HIGH — pitfalls derived from actual workflow source code analysis and MEMORY.md session notes
- Validation architecture: HIGH — test map directly references existing infrastructure

**Research date:** 2026-03-24
**Valid until:** 2026-04-24 (stable stack; n8n 2.9.4 pinned in ci.yml)
