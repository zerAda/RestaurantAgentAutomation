# Phase 8: n8n E2E Test Implementation — Research

**Researched:** 2026-03-28
**Domain:** n8n 2.9.4 E2E test scripting, Redis queue assertion, GitHub Actions CI lifecycle management
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TEST-09 | E2E test: POST to `/v1/inbound/whatsapp` with valid Meta-signed payload triggers W_IN_WHATSAPP_ADAPTER and creates a record in `inbound_messages` (direct Postgres, NOT Strapi) | Write path confirmed from W1_IN_WA.json node "B0 - RateLimit + Log" (node ID 25e66261); writes directly to n8n Postgres DB via `INSERT INTO inbound_messages`; assertion: `SELECT COUNT(*) FROM inbound_messages WHERE msg_id = '...'` |
| TEST-10 | E2E test: failed outbound message is retried with exponential backoff — verify Redis queue entry exists after first failure | W15_OUTBOX_WORKER.json uses `ralphe:outbox:pending` Redis list; on retryable failure with attempts < maxAttempts(7), LPUSHes back with attempts+1 and future nextRetryAt; test seeds entry, triggers W15 via REST API, verifies re-queue |
| TEST-11 | Workflow smoke tests run in CI using n8n test mode or mock webhook triggers, without requiring a live VPS | New `n8n-workflow-e2e` CI job with inline stack lifecycle: compose up, migrations, fixtures, n8n startup, owner setup, login, workflow import, DB activation, n8n restart, run test-n8n-e2e.sh, compose down |
</phase_requirements>

---

## Summary

Phase 8 is a gap-closure phase that executes the work from Phase 5 (blocked since 2026-03-24). The plans already exist in `05-01-PLAN.md` and `05-02-PLAN.md` with detailed task specifications. The four blockers identified in the 2026-03-24 session have been partially resolved by subsequent work: `docker/docker-compose.test.yml` already has `META_APP_SECRET`, `META_SIGNATURE_REQUIRED`, and `REDIS_CREDENTIAL_ID` env vars (lines 66-68), and `scripts/smoke-n8n-e2e.sh` exists as a VPS-targeting smoke script. However, the primary deliverables for Phase 8 are still missing: `scripts/test-n8n-e2e.sh` (the full E2E script with DB assertions that runs against the docker-compose.test.yml stack) and the `n8n-workflow-e2e` CI job.

The existing `scripts/smoke-n8n-e2e.sh` targets the production VPS (`https://api.srv1258231.hstgr.cloud`), has no DB assertions for `inbound_messages`, and does not verify the outbox retry mechanism. It is a different artifact from the required `scripts/test-n8n-e2e.sh`. The CI job `smoke-n8n-e2e` already in ci.yml only does a syntax check and dry-run against localhost:5678 with no compose stack. The full `n8n-workflow-e2e` job described in `05-02-PLAN.md` — with inline stack lifecycle, workflow import, activation, and actual test execution — has not been added to ci.yml.

**Primary recommendation:** Phase 8 has two plans. Plan 08-01 creates `scripts/test-n8n-e2e.sh` (TEST-09, TEST-10) reusing the patterns already documented in `05-01-PLAN.md`. Plan 08-02 wires the full CI job (TEST-11) exactly as specified in `05-02-PLAN.md`. The existing Phase 5 plan files are the authoritative spec; Phase 8 re-executes them with the 4 blockers pre-resolved.

---

## Pre-Resolved Blockers (from 2026-03-24 session)

The 4 blockers that stopped Phase 5 have been resolved or can be resolved definitively:

| Blocker | Status | Resolution |
|---------|--------|------------|
| Plan 02 Task 1: CI job missing compose lifecycle | RESOLVED IN PLAN — 05-02-PLAN.md now has full inline stack lifecycle (confirmed by reading file) | Execute exactly as specified in 05-02-PLAN.md Task 1 |
| Plan 01 Task 2: TEST-09 assertion path unresolved | RESOLVED — W1_IN_WA writes directly to Postgres `inbound_messages` via node "B0 - RateLimit + Log" (confirmed in 05-01-PLAN.md interfaces section) | Use `SELECT COUNT(*) FROM inbound_messages WHERE msg_id = '...'` assertion against n8n Postgres DB |
| Plan 02 Task 1 action: compose lifecycle missing | RESOLVED IN PLAN — 05-02-PLAN.md Task 1 action block contains the complete 8-step inline setup sequence | Execute as-is |
| VALIDATION.md out of sync | N/A FOR PHASE 8 — Phase 8 creates a new VALIDATION.md for its own 3-task structure | Phase 8 VALIDATION.md should reflect TEST-09/TEST-10 (08-01) and TEST-11 (08-02) |

**2 warnings from 2026-03-24 session:**
- Plan 01 missing REDIS_CREDENTIAL_ID in compose env: **Already fixed** — docker-compose.test.yml line 68 has `REDIS_CREDENTIAL_ID: ${REDIS_CREDENTIAL_ID:-43SDqJYMGa6RvFqW}`
- Plan 01 Truth 3 is impl-focused: **Address in 08-VALIDATION.md** — rephrase as observable truth

---

## Current State of Artifacts

### docker/docker-compose.test.yml
**Status: COMPLETE** — META_APP_SECRET, META_SIGNATURE_REQUIRED, REDIS_CREDENTIAL_ID are already present (lines 66-68):
```yaml
META_APP_SECRET: ${META_APP_SECRET:-ci-test}
META_SIGNATURE_REQUIRED: ${META_SIGNATURE_REQUIRED:-warn}
REDIS_CREDENTIAL_ID: ${REDIS_CREDENTIAL_ID:-43SDqJYMGa6RvFqW}
```
**Note:** `META_SIGNATURE_REQUIRED` defaults to `warn` (not `enforce`). The test script should use `enforce` mode for its test but this can be overridden via env var at runtime. No changes needed to docker-compose.test.yml.

### scripts/smoke-n8n-e2e.sh
**Status: EXISTS BUT WRONG ARTIFACT** — This is a VPS-targeting smoke script. It targets `https://api.srv1258231.hstgr.cloud`, has no DB assertions, does not verify outbox retry. It is NOT the required `scripts/test-n8n-e2e.sh`. Do not confuse or overwrite it.

### scripts/test-n8n-e2e.sh
**Status: MISSING** — The primary deliverable of Plan 08-01. Must be created.

### .github/workflows/ci.yml — n8n-workflow-e2e job
**Status: MISSING** — Only `smoke-n8n-e2e` job exists (syntax check + dry-run, no compose stack). The full `n8n-workflow-e2e` job with inline compose lifecycle must be added.

### .github/workflows/ci.yml — smoke-n8n-e2e job
**Status: EXISTS** — Already wired (job 6d, line 754). Runs `smoke-n8n-e2e.sh` syntax check + localhost dry-run. This is separate from the `n8n-workflow-e2e` job. Both should coexist.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| n8n | 2.9.4 | Workflow runtime under test | Production version per VPS and ci.yml `env.N8N_VERSION` |
| postgres | 16-alpine (test) | Assertion DB — query `inbound_messages` | docker-compose.test.yml uses `postgres:16-alpine`; note: integration-tests job uses 15-alpine/16-alpine matrix |
| redis | 7-alpine | Assertion store — `ralphe:outbox:pending` queue entries | Production Redis version in docker-compose.test.yml |
| nginx | 1.27-alpine | Gateway — routes POSTs to n8n webhooks | Production gateway version in docker-compose.test.yml |
| openssl | (system) | HMAC-SHA256 signature generation for Meta-signed payloads | Already used in `scripts/test_e2e.sh` `generate_signature()` |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| jq | (system) | Parse n8n REST API responses | Already used in test_harness.sh |
| redis-cli | (redis:7-alpine) | Query Redis list entries after outbox test | `docker compose exec redis redis-cli LLEN / LRANGE / LINDEX` |
| psql | (postgres:16-alpine) | Query `inbound_messages` after async processing | `docker compose exec -T postgres sh -lc "psql -U n8n -d n8n -Atc ..."` |
| mock-api | node:18-alpine | Stub outbound send URLs (WA_SEND_URL, IG_SEND_URL, MSG_SEND_URL) | Configured in docker-compose.test.yml at `http://mock-api:8080/{send/wa,send/ig,send/msg}` |
| curl | (system) | HTTP requests to n8n webhooks and REST API | Already in test_harness.sh |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bash + curl test script | Python pytest + httpx | Python used for unit tests; bash matches existing smoke script convention; keep consistency |
| Reuse test_harness.sh for CI setup | Inline stack lifecycle in new job | test_harness.sh tears down at step 8 (line 551: `docker compose down -v`); cannot be used for setup-only; must inline |
| /webhook-test/ URL path | Production /webhook/ path | /webhook-test/ requires n8n editor open; in headless CI only activated /webhook/ path works |

**Installation:**
```bash
# No new packages needed — all dependencies already in docker-compose.test.yml
# Scripts only require: bash, curl, jq, openssl, docker
```

---

## Architecture Patterns

### Files to Create/Modify
```
scripts/
├── test-n8n-e2e.sh          # CREATE: Full E2E test script (TEST-09, TEST-10)
└── smoke-n8n-e2e.sh         # EXISTING: Do NOT modify (VPS smoke script, different purpose)
.github/workflows/
└── ci.yml                   # MODIFY: Add n8n-workflow-e2e job (TEST-11); update ci-summary
docker/
└── docker-compose.test.yml  # ALREADY COMPLETE: No changes needed
```

### Pattern 1: Meta-Signed Inbound Payload (TEST-09)

**What:** Generate HMAC-SHA256 signatures for Meta-native WhatsApp webhook payloads so W1_IN_WA processes them end-to-end.

**When to use:** TEST-09 — POST to webhook, verify `inbound_messages` DB row created.

**Critical constraint:** W1_IN_WA verifies HMAC on `$json.rawBody` (the raw string, not parsed JSON). n8n webhook node with `rawBody: true` captures the raw request body. The HMAC must be computed over the exact bytes sent as the POST body. Do not re-serialize.

```bash
# Source: scripts/test_e2e.sh + W1_IN_WA.json B0 node
generate_meta_sig() {
  local payload="$1"
  local secret="${META_APP_SECRET:-test_meta_app_secret_for_e2e}"
  echo -n "$payload" | openssl dgst -sha256 -hmac "$secret" | sed 's/^.* //'
}

MSG_ID="e2e-wa-$(date +%s)-$$"
# Build payload as single line (no newlines — rawBody must match exactly)
PAYLOAD="{\"object\":\"whatsapp_business_account\",\"entry\":[{\"id\":\"TEST_WA_ID\",\"changes\":[{\"value\":{\"messaging_product\":\"whatsapp\",\"metadata\":{\"display_phone_number\":\"15550000000\",\"phone_number_id\":\"TEST_PHONE_ID\"},\"messages\":[{\"from\":\"15551234567\",\"id\":\"${MSG_ID}\",\"timestamp\":\"$(date +%s)\",\"text\":{\"body\":\"Bonjour je veux commander\"},\"type\":\"text\"}]},\"field\":\"messages\"}]}]}"
SIG="sha256=$(generate_meta_sig "$PAYLOAD")"

WH_STATUS=$(curl -s -o /tmp/wh_resp.json -w "%{http_code}" \
  -X POST "http://localhost:25678/webhook/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature-256: ${SIG}" \
  -d "${PAYLOAD}")
```

### Pattern 2: Async DB Polling for inbound_messages (TEST-09 assertion)

**What:** Poll `inbound_messages` table for the test `msg_id` with timeout, because n8n queue mode processes asynchronously.

**Critical constraint:** n8n in queue mode: HTTP 200 ACK is returned before workflow executes. Must poll; do not assert immediately after POST.

```bash
# Source: scripts/test_harness.sh polling pattern
poll_for_record() {
  local msg_id="$1" max_wait="${2:-20}"
  local waited=0 count
  while [ "${waited}" -lt "${max_wait}" ]; do
    count=$(docker compose -f "${COMPOSE_FILE}" exec -T postgres sh -lc \
      "psql -U n8n -d n8n -Atc \"SELECT COUNT(*) FROM inbound_messages WHERE msg_id = '${msg_id}';\"" \
      | tr -d '\r\n')
    [ "${count:-0}" -ge 1 ] && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}
```

### Pattern 3: Redis Outbox Failure Seeding + Verification (TEST-10)

**What:** Seed a failing entry in `ralphe:outbox:pending`, trigger W15, verify the entry is re-queued with `attempts+1` and future `nextRetryAt`.

**Critical constraints from W15_OUTBOX_WORKER.json:**
- RPOP from `ralphe:outbox:pending` (pops from tail, FIFO)
- On retryable failure with `attempts < maxAttempts(7)`: LPUSH back (to head) with `attempts+1` and `nextRetryAt = now + baseDelaySec * 2^(attempts-1)`
- Uses `"id": "={{ $env.REDIS_CREDENTIAL_ID }}"` — REDIS_CREDENTIAL_ID already set in docker-compose.test.yml to `43SDqJYMGa6RvFqW`
- `continueOnFail: true` means Redis errors are silent — verify via Redis CLI, not n8n execution logs

```bash
# Flush Redis outbox before test to avoid leftover entries
docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli DEL ralphe:outbox:pending ralphe:outbox:dlq

# Seed a failing entry (attempts=1, well below maxAttempts=7)
OUTBOX_ENTRY="{\"channel\":\"whatsapp\",\"payload\":{\"userId\":\"retry-test-$RANDOM\",\"replyText\":\"test retry\"},\"attempts\":1,\"nextRetryAt\":null,\"outboxMsgId\":\"e2e-retry-$$\"}"
docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli LPUSH ralphe:outbox:pending "${OUTBOX_ENTRY}"

# Trigger W15 manually via n8n REST API (bypass 30s CRON)
W15_ID=$(docker compose -f "${COMPOSE_FILE}" exec -T postgres sh -lc \
  "psql -U n8n -d n8n -Atc \"SELECT id FROM workflow_entity WHERE name LIKE '%Outbox Worker%' LIMIT 1;\"" \
  | tr -d '\r\n')

curl -s -b "${N8N_JAR}" \
  -X POST "http://localhost:25678/rest/workflows/${W15_ID}/run" \
  -H "Content-Type: application/json" \
  -d '{}' >/dev/null

sleep 5  # Allow execution to complete

# Verify entry re-queued with attempts=2
QUEUE_LEN=$(docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli LLEN ralphe:outbox:pending | tr -d '\r\n')
[ "${QUEUE_LEN:-0}" -ge 1 ] || fail "TEST-10: entry not re-queued"

LAST_ENTRY=$(docker compose -f "${COMPOSE_FILE}" exec -T redis redis-cli LINDEX ralphe:outbox:pending 0 | tr -d '\r\n')
ATTEMPTS=$(echo "${LAST_ENTRY}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('attempts',0))" 2>/dev/null || echo "0")
[ "${ATTEMPTS}" -eq 2 ] || fail "TEST-10: attempts not incremented (got ${ATTEMPTS}, expected 2)"
```

### Pattern 4: CI Job Inline Stack Lifecycle (TEST-11)

**What:** Each GitHub Actions job runs on a fresh ubuntu-latest runner with no shared state. The `n8n-workflow-e2e` job MUST manage its own full stack lifecycle inline.

**Why inline:** `test_harness.sh` tears down the stack at step 8 (line 551: `docker compose down -v`) — it cannot be used for setup-only. The new CI job replicates steps 1-5 of test_harness.sh without the teardown.

**Job structure (8 steps in ci.yml):**
1. Checkout code
2. Start compose stack + postgres readiness wait + strapi DB creation + migrations + fixture seeding + n8n start + readiness wait
3. Owner setup + login + workflow import (W4_CORE, W1_IN_WA, W2_IN_IG, W3_IN_MSG, W15_OUTBOX_WORKER) + DB activation + n8n restart + readiness wait
4. Run `bash scripts/test-n8n-e2e.sh`
5. Collect Docker logs on failure
6. Upload failure artifacts (actions/upload-artifact SHA-pinned)
7. Tear down compose stack (`if: always()`)

**Position in ci.yml:** Between `test-harness` job and `ci-summary` job. Needs: `[integrity-gate, test-harness]`. If: `main` or `release/*` branches.

### Pattern 5: n8n Workflow Activation (n8n 2.x)

**Critical n8n 2.x constraint:** `PATCH /rest/workflows/:id` with `{active: true}` returns `active: unknown` (known bug). Use direct SQL instead:

```bash
# Source: scripts/test_harness.sh + 05-02-PLAN.md Task 1
docker compose -f "${COMPOSE_FILE}" exec -T postgres sh -lc \
  "psql -U n8n -d n8n -Atc \"UPDATE workflow_entity SET active = true WHERE id IN ('${WF_ID}');\""

# After DB activation, MUST restart n8n to register webhook routes
docker compose -f "${COMPOSE_FILE}" stop n8n
docker compose -f "${COMPOSE_FILE}" up -d n8n
# Wait for /rest/settings + 5s buffer for async webhook registration
```

### Anti-Patterns to Avoid

- **Using /webhook-test/ path:** Requires n8n editor open. In CI with headless n8n, only `/webhook/` production path works.
- **Asserting HTTP 200 as proof of processing:** n8n fast-ACK returns 200 immediately. A 200 does NOT mean the workflow executed or DB row was created. Always poll `inbound_messages`.
- **Not restarting n8n after DB activation:** `ActiveWorkflowManager.init()` registers webhook Express routes on startup. If you activate via DB without restart, webhook routes are not registered and POSTs return 404.
- **Forgetting to flush Redis before TEST-10:** Leftover entries from previous runs will cause LLEN to be > 1 regardless of test outcome.
- **Using test_harness.sh as CI setup:** It tears down the compose stack at step 8. Cannot be used as a setup step for a subsequent test.
- **Overwriting smoke-n8n-e2e.sh:** This existing script targets the VPS and is used by the existing `smoke-n8n-e2e` CI job. The new script is `test-n8n-e2e.sh` (different name, different purpose).
- **META_SIGNATURE_REQUIRED=enforce without Redis credential:** The REDIS_CREDENTIAL_ID is already set to `43SDqJYMGa6RvFqW` in docker-compose.test.yml, but this credential must exist in the n8n credentials table. It must be created via `POST /rest/credentials` during test setup if not using a persistent volume.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| n8n workflow import | Custom import script | Existing `create_wf()` pattern from test_harness.sh (lines 86-170) | Already handles n8n 2.x API, ownership, and auth |
| Meta HMAC signature | Custom crypto | `openssl dgst -sha256 -hmac` already in test_e2e.sh | Proven correct in existing tests |
| DB polling with timeout | Custom retry loop | Pattern from test_harness.sh `for i in $(seq 1 20); do ... sleep 1; done` | Already battle-tested |
| Mock outbound API | Custom mock server | Existing `mock-api` container in docker-compose.test.yml | Already configured with WA_SEND_URL pointing to mock-api:8080/send/wa |
| Redis queue inspection | Manual RESP | `docker compose exec redis redis-cli LLEN / LRANGE / LINDEX` | Redis CLI already in redis:7-alpine image |
| Postgres assertions | Direct TCP | `docker compose exec -T postgres sh -lc "psql -U n8n -d n8n -Atc '...'"` | Already in test_harness.sh pattern |

**Key insight:** Every helper function and pattern needed for `test-n8n-e2e.sh` already exists in `scripts/test_harness.sh` and `scripts/test_e2e.sh`. The script assembles these proven patterns rather than inventing new ones.

---

## Common Pitfalls

### Pitfall 1: REDIS_CREDENTIAL_ID vs. Redis Queue Access
**What goes wrong:** W15_OUTBOX_WORKER uses `"id": "={{ $env.REDIS_CREDENTIAL_ID }}"` for credential resolution. If the credential ID doesn't exist in n8n's `credentials_entity` table, Redis operations fail silently (`continueOnFail: true`). The test entry never gets popped or re-queued.
**Why it happens:** docker-compose.test.yml sets `REDIS_CREDENTIAL_ID=43SDqJYMGa6RvFqW`, but this credential must be created in the n8n instance via the REST API after startup. The credential ID is just a reference; the actual credential object with `host=redis`, `port=6379` must exist.
**How to avoid:** During CI job setup, after n8n login, create the Redis credential via `POST /rest/credentials` with the known ID, or query the DB to get the auto-assigned ID. Alternatively, set `REDIS_CREDENTIAL_ID` to the ID returned by the credential creation call.
**Warning signs:** `LLEN ralphe:outbox:pending` stays at 1 after W15 execution — entry was neither processed nor re-queued. Check n8n execution logs for credential errors.

### Pitfall 2: n8n Queue Mode Webhook Activation Race
**What goes wrong:** After DB activation + n8n restart, the webhook routes are not immediately available. Posting to the webhook returns 404.
**Why it happens:** n8n 2.x's `ActiveWorkflowManager.init()` is async. The API responding at `/rest/settings` does not guarantee webhook routes are registered.
**How to avoid:** After n8n restart and readiness wait, add `sleep 5` as an extra buffer. Alternatively, retry the webhook POST with backoff for up to 45 seconds.
**Warning signs:** `WH_STATUS=404` on the first POST to `/webhook/v1/inbound/whatsapp`.

### Pitfall 3: single-line JSON requirement for HMAC
**What goes wrong:** Multi-line JSON in shell heredocs gets extra whitespace or newlines that change the raw body bytes. The HMAC computed over the multi-line string will not match the HMAC n8n computes over the network bytes.
**Why it happens:** n8n's rawBody captures exactly what was received over the wire. Bash heredocs can introduce trailing newlines.
**How to avoid:** Build the payload as a single-line JSON string using string interpolation, not heredoc. Use `echo -n` (not `echo`) when computing the HMAC.
**Warning signs:** HTTP 200 ACK but n8n logs show `metaSigReason=sig_mismatch`; no row appears in `inbound_messages`.

### Pitfall 4: outbox:pending vs. outbox:dlq confusion
**What goes wrong:** After W15 runs on a seeded entry, the queue is empty instead of having an entry with `attempts=2`. The entry went to `ralphe:outbox:dlq` because the seeded JSON was malformed or `retryable` was false.
**Why it happens:** W15 only re-queues if `retryable=true` AND `attempts < maxAttempts`. If the seed entry has a non-retryable channel or bad JSON, it goes to DLQ.
**How to avoid:** Seed with `{"channel":"whatsapp","attempts":1,"retryable":true,...}` and use an outboxMsgId that is unique. Point WA_SEND_URL to mock-api:8080/send/wa which returns 500 for the test.
**Warning signs:** `LLEN ralphe:outbox:pending` = 0 and `LLEN ralphe:outbox:dlq` = 1 — check the seed entry structure.

### Pitfall 5: ci-summary needs update when adding new CI job
**What goes wrong:** The new `n8n-workflow-e2e` job is added to ci.yml but ci-summary's `needs` array and summary table are not updated. The YAML is syntactically valid but the summary job doesn't wait for the new job, causing race conditions and incomplete status reports.
**How to avoid:** When adding the `n8n-workflow-e2e` job, simultaneously add it to `ci-summary.needs` and the summary table `cat >> $GITHUB_STEP_SUMMARY` block. Also update the dependency graph comment at the top of ci.yml.
**Warning signs:** CI passes but ci-summary completes before `n8n-workflow-e2e` finishes; `n8n-workflow-e2e` failures do not block the PR.

### Pitfall 6: Credential creation timing in CI
**What goes wrong:** The Redis credential is created in the "Import and activate workflows" CI step, but W15_OUTBOX_WORKER is imported in that same step. If the credential creation call returns the credential with a different ID than `43SDqJYMGa6RvFqW`, the hardcoded REDIS_CREDENTIAL_ID env var won't match.
**Why it happens:** n8n assigns credential IDs from a nanoid generator. The env var `REDIS_CREDENTIAL_ID` is used at runtime by W15. The credential ID in the DB must match the env var.
**How to avoid:** Create the Redis credential via `POST /rest/credentials` with the body specifying the known test credential data, then capture the returned `id`. If the returned `id` differs from the env var value, either update the env var in the compose environment or use the n8n API to set the credential ID explicitly (some n8n versions accept `id` in the create payload).
**Alternative:** Use the approach in test_harness.sh that reads the credential ID from the DB after creation and exports it as `REDIS_CREDENTIAL_ID`.

---

## Code Examples

### Full test-n8n-e2e.sh Script Structure
```bash
#!/usr/bin/env bash
# Source: 05-01-PLAN.md Task 2 specification
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker/docker-compose.test.yml}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
META_APP_SECRET="${META_APP_SECRET:-test_meta_app_secret_for_e2e}"
N8N_URL="${N8N_URL:-http://localhost:25678}"
N8N_JAR="/tmp/n8n_e2e_cookies"
PASS=0; FAIL=0; SKIP=0

cd "$ROOT_DIR"

pass() { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1 -- $2"; }
skip() { SKIP=$((SKIP+1)); echo "SKIP: $1 -- $2"; }

generate_meta_sig() {
  echo -n "$1" | openssl dgst -sha256 -hmac "${META_APP_SECRET}" | sed 's/^.* //'
}

# TEST-09: Meta-signed WA inbound -> inbound_messages DB row
# TEST-10: Outbox retry seeding -> Redis re-queue with attempts+1
# SUMMARY: exit 1 if FAIL > 0
```

### n8n REST API Credential Creation
```bash
# Source: n8n REST API (verified against n8n 2.9.4 test_harness.sh patterns)
# Create Redis credential during CI setup after login
REDIS_CRED_PAYLOAD="{\"name\":\"Redis Test\",\"type\":\"redis\",\"data\":{\"host\":\"redis\",\"port\":6379,\"db\":0}}"
CRED_RESP=$(curl -s -b "${N8N_JAR}" \
  -X POST "http://localhost:25678/rest/credentials" \
  -H "Content-Type: application/json" \
  -d "${REDIS_CRED_PAYLOAD}")
CRED_ID=$(echo "${CRED_RESP}" | jq -r '.data.id // .id // empty')
export REDIS_CREDENTIAL_ID="${CRED_ID}"
```

### ci.yml Job Dependencies (updated graph comment)
```
# integrity-gate --> lint-validate
#                --> python-tests
#                --> integration-tests [matrix: pg15, pg16]
#                --> docker-build (main/release only)
#                --> security-scan
#                --> frontend-lint
#                --> test-harness (main/release only, needs: integration-tests)
#                       |
#                --> n8n-workflow-e2e (main/release only, needs: integrity-gate, test-harness)
#                       |
#                  ci-summary (needs: all, if: always())
```

### ci-summary needs update
```yaml
ci-summary:
  needs:
    - integrity-gate
    - lint-validate
    - python-tests
    - integration-tests
    - integration-tests-pg16
    - cms-ts-compile
    - docker-build
    - security-scan
    - frontend-lint
    - test-harness
    - smoke-nginx-routing
    - smoke-strapi-permissions
    - smoke-n8n-e2e
    - n8n-workflow-e2e   # ADD THIS
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `PATCH /rest/workflows/:id` for activation | SQL `UPDATE workflow_entity SET active = true` | n8n 2.0 | PATCH returns `active=unknown`; DB UPDATE is the only reliable activation method |
| n8n CLI `n8n import:workflow` | REST API `POST /rest/workflows` | n8n 2.x queue mode | CLI hangs in queue mode (per MEMORY.md); REST API is the only reliable import method |
| /webhook-test/ path (editor-required) | /webhook/ production path | n8n 1.x -> 2.x | Tests must activate workflows and use /webhook/ |
| webhook_entity table | workflow_entity.active field | n8n 2.0 | webhook_entity was removed; activation state lives in workflow_entity |
| Strapi inbound-message HTTP write (ROADMAP says this) | Direct Postgres INSERT to inbound_messages | W1_IN_WA.json confirmed | TEST-09 assertion must query Postgres directly, not Strapi; no Strapi instance needed for TEST-09 |

**Deprecated/outdated:**
- n8n CLI import in queue mode: hangs (per MEMORY.md 2026-03-08); use REST API
- ROADMAP TEST-09 description "creates a record in Strapi inbound-message": **INACCURATE** — W1_IN_WA writes directly to n8n Postgres DB, not to Strapi. This was resolved in Phase 5 research (05-01-PLAN.md interfaces section).

---

## Open Questions

1. **REDIS_CREDENTIAL_ID: 43SDqJYMGa6RvFqW vs. dynamically assigned ID**
   - What we know: docker-compose.test.yml sets `REDIS_CREDENTIAL_ID=43SDqJYMGa6RvFqW` as the default. n8n 2.9.4 assigns credential IDs using nanoid when created via REST API.
   - What's unclear: Whether n8n 2.9.4 accepts a pre-specified `id` field in the `POST /rest/credentials` body (which would allow forcing the ID to match the env var).
   - Recommendation: Plan 08-01 should create the Redis credential via REST API, capture the returned ID, and export it as `REDIS_CREDENTIAL_ID` for the duration of the test run. This is the safest approach regardless of whether n8n accepts pre-specified IDs.

2. **W15_OUTBOX_WORKER manual trigger via REST API**
   - What we know: Phase 5 research identified `POST /rest/workflows/:id/run` as the manual trigger endpoint (marked LOW confidence). test_harness.sh does not use this endpoint.
   - What's unclear: Whether `POST /rest/workflows/:id/run` works correctly in n8n 2.9.4 queue mode, or if manual triggers dispatch via the Bull queue (which would add latency).
   - Recommendation: Implement the REST API trigger approach. If it fails, fall back to waiting 35 seconds for the CRON trigger. Both should be attempted in order.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash + curl + psql + redis-cli (same as test_harness.sh) |
| Config file | docker/docker-compose.test.yml (existing, already complete) |
| Quick run command | `bash -n scripts/test-n8n-e2e.sh` (syntax check, no Docker) |
| Full suite command | `bash scripts/test-n8n-e2e.sh` (requires running compose stack) |
| Estimated runtime | ~90 seconds (excluding stack startup) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEST-09 | Meta-signed WA POST -> W1_IN_WA executes -> `inbound_messages` row in Postgres | integration | `bash scripts/test-n8n-e2e.sh` | No — Wave 0 |
| TEST-10 | Seed failing outbox entry -> W15 executes -> re-queued with attempts+1 + future nextRetryAt | integration | `bash scripts/test-n8n-e2e.sh` | No — Wave 0 |
| TEST-11 | Workflow E2E tests run in CI without live VPS (full compose lifecycle) | CI integration | `n8n-workflow-e2e` CI job in ci.yml | No — Wave 0 |

### Sampling Rate
- **Per task commit:** `bash -n scripts/test-n8n-e2e.sh` (syntax check, no Docker required)
- **Per wave merge:** `bash scripts/test-n8n-e2e.sh` (full stack run — requires compose stack)
- **Phase gate:** Full suite green (`test_harness.sh` passing AND `test-n8n-e2e.sh` passing) before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `scripts/test-n8n-e2e.sh` — covers TEST-09 (Meta-signed WA inbound + Postgres DB assertion) and TEST-10 (outbox retry seeding + Redis re-queue verification)
- [ ] `.github/workflows/ci.yml` — new `n8n-workflow-e2e` job with inline full compose lifecycle (covers TEST-11); update ci-summary `needs` and summary table

*(docker/docker-compose.test.yml already has all required env vars — no Wave 0 gap there)*

---

## Sources

### Primary (HIGH confidence)
- `.planning/phases/05-test-coverage-n8n-workflow-e2e/05-01-PLAN.md` — Complete task specification for test-n8n-e2e.sh; interfaces block with confirmed W1_IN_WA write path; inbound_messages schema
- `.planning/phases/05-test-coverage-n8n-workflow-e2e/05-02-PLAN.md` — Complete task specification for n8n-workflow-e2e CI job; full 8-step inline stack lifecycle; SHA-pinned action versions
- `.planning/phases/05-test-coverage-n8n-workflow-e2e/05-RESEARCH.md` — Architecture patterns, pitfalls, code examples for Meta HMAC, DB polling, Redis queue inspection
- `docker/docker-compose.test.yml` — Current state: META_APP_SECRET, META_SIGNATURE_REQUIRED, REDIS_CREDENTIAL_ID already present
- `.github/workflows/ci.yml` — Current CI structure; existing smoke-n8n-e2e job (lines 752-775); ci-summary needs list; SHA-pinned action versions
- `scripts/smoke-n8n-e2e.sh` — Existing VPS smoke script; confirmed different artifact from required test-n8n-e2e.sh
- `scripts/test_harness.sh` — Reusable patterns: compose lifecycle, n8n login, workflow import, DB activation, DB polling, webhook testing

### Secondary (MEDIUM confidence)
- n8n 2.x breaking changes (MEMORY.md 2026-03-01) — PATCH activation returns `active=unknown`; use SQL UPDATE; login field is `emailOrLdapLoginId`; import via HTTP not CLI
- n8n session notes (MEMORY.md 2026-03-08) — n8n CLI import hangs in queue mode; use Node.js HTTP request to localhost:5678

### Tertiary (LOW confidence)
- `POST /rest/workflows/:id/run` for manual trigger — referenced in 05-RESEARCH.md Pattern 4 as LOW confidence; not used in test_harness.sh; needs verification at execution time

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components verified against existing docker-compose.test.yml and ci.yml
- Architecture: HIGH — patterns extracted directly from 05-01-PLAN.md, 05-02-PLAN.md, and test_harness.sh
- Current artifact state: HIGH — read actual files (smoke-n8n-e2e.sh, docker-compose.test.yml, ci.yml)
- Pitfalls: HIGH — derived from Phase 5 research + actual workflow source code + MEMORY.md session notes
- Validation architecture: HIGH — directly references existing infrastructure

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (stable stack; n8n 2.9.4 pinned in ci.yml env.N8N_VERSION)
