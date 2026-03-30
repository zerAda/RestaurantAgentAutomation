---
phase: 08-n8n-e2e-test-implementation
verified: 2026-03-30T00:00:00Z
status: passed
score: 6/6 must-haves verified
re_verification: false
---

# Phase 08: n8n E2E Test Implementation — Verification Report

**Phase Goal:** `scripts/test-n8n-e2e.sh` exists and verifies that the WA inbound adapter creates an `inbound_messages` DB row (direct Postgres write, not Strapi) and that outbound failures produce a Redis retry entry; CI executes these tests via a full compose stack lifecycle

**Verified:** 2026-03-30
**Status:** passed
**Re-verification:** No — initial verification

---

## Must-Haves Source

Must-haves extracted from PLAN frontmatter (both `08-01-PLAN.md` and `08-02-PLAN.md`).

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A POST with a valid Meta-signed WhatsApp payload creates a row in `inbound_messages` in the n8n Postgres DB (direct write by W1_IN_WA node B0, NOT Strapi HTTP) | VERIFIED | `scripts/test-n8n-e2e.sh` line 55: `SELECT COUNT(*) FROM inbound_messages WHERE msg_id = '${msg_id}'`; HMAC computed over exact payload bytes; 20s async poll accounts for n8n queue-mode fast-ACK |
| 2 | A failing outbox entry seeded into `ralphe:outbox:pending` is re-queued with attempts incremented from 1 to 2 and a future `nextRetryAt` timestamp | VERIFIED | `scripts/test-n8n-e2e.sh` lines 129-165: seeds entry with `"attempts":1,"retryable":true`, triggers W15, polls `LINDEX ralphe:outbox:pending 0` and asserts `attempts >= 2` via python3 JSON parse |
| 3 | `scripts/test-n8n-e2e.sh` is a standalone bash script that reports PASS/FAIL/SKIP counts and exits 1 on any failure | VERIFIED | File exists (185 lines, >= 150 minimum), `bash -n` syntax check passes, lines 183-185: `PASS/FAIL/SKIP` counters echoed and `exit 1` on `FAIL > 0` |
| 4 | Workflow E2E tests run in CI on main and release branches without a live VPS | VERIFIED | `ci.yml` job `n8n-workflow-e2e` at line 838: `if: github.ref == 'refs/heads/main' \|\| startsWith(github.ref, 'refs/heads/release/')`, timeout-minutes: 30, full inline stack lifecycle |
| 5 | The CI job starts its own docker compose stack, imports workflows, runs tests, and tears down | VERIFIED | Lines 856-1054 of `ci.yml`: `docker compose up -d postgres redis mock-api`, postgres wait, strapi DB creation, migrations, fixtures, n8n start, owner setup, login, `POST /rest/workflows` import loop (W4_CORE, W1_IN_WA, W2_IN_IG, W3_IN_MSG, W9_ADMIN_PING, W15_OUTBOX_WORKER), Redis credential creation, DB activation via `UPDATE workflow_entity SET active = true`, n8n restart + readiness wait, `bash scripts/test-n8n-e2e.sh`, teardown `docker compose down -v --remove-orphans` with `if: always()` |
| 6 | CI failure in E2E tests uploads Docker logs as artifacts for debugging | VERIFIED | Lines 1033-1049 of `ci.yml`: failure step collects compose logs, docker ps, redis-outbox, redis-dlq, inbound-messages DB query; `actions/upload-artifact@65462800fd760344b1a7b4382951275a0abb4808` SHA-pinned, path `n8n-e2e-logs/`, retention-days: 14 |

**Score:** 6/6 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/test-n8n-e2e.sh` | E2E test script for inbound adapter and outbox retry; min 150 lines | VERIFIED | 185 lines; `bash -n` exits 0; created in commit `ce9e174`; covers TEST-09 + TEST-10 |
| `.github/workflows/ci.yml` | Contains `n8n-workflow-e2e` job with full compose stack lifecycle | VERIFIED | Job added in commit `8780a67` (Phase 09-02 session, pre-existing when 08-02 executed per SUMMARY note); all acceptance criteria confirmed |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `scripts/test-n8n-e2e.sh` | `docker/docker-compose.test.yml` | `COMPOSE_FILE` variable | WIRED | Line 18: `COMPOSE_FILE="${COMPOSE_FILE:-docker/docker-compose.test.yml}"` matches plan pattern exactly |
| `scripts/test-n8n-e2e.sh` | `inbound_messages` table (n8n Postgres DB) | `psql SELECT` after webhook POST | WIRED | Line 55: `SELECT COUNT(*) FROM inbound_messages WHERE msg_id = '${msg_id}'` via `docker compose exec -T postgres` — matches plan pattern |
| `scripts/test-n8n-e2e.sh` | `ralphe:outbox:pending` Redis list | `redis-cli LPUSH` then `LINDEX` | WIRED | Line 130: `redis-cli LPUSH ralphe:outbox:pending`, line 162: `redis-cli LINDEX ralphe:outbox:pending 0` — 4 references total, >= 3 required |
| `ci.yml (n8n-workflow-e2e)` | `scripts/test-n8n-e2e.sh` | `bash scripts/test-n8n-e2e.sh` invocation | WIRED | Lines 1030-1031: `chmod +x scripts/test-n8n-e2e.sh` + `bash scripts/test-n8n-e2e.sh` |
| `ci.yml (n8n-workflow-e2e)` | `docker/docker-compose.test.yml` | `docker compose -f docker/docker-compose.test.yml up -d` | WIRED | Line 856: `docker compose -f "$COMPOSE_FILE" up -d postgres redis mock-api` |
| `ci.yml (n8n-workflow-e2e)` | `docker/docker-compose.test.yml` | `docker compose ... down` | WIRED | Line 1054: `docker compose -f docker/docker-compose.test.yml down -v --remove-orphans` with `if: always()` |
| `ci.yml (ci-summary)` | `ci.yml (n8n-workflow-e2e)` | `needs` dependency | WIRED | Line 1076: `- n8n-workflow-e2e` in ci-summary `needs` array; line 1098: summary table row present |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| TEST-09 | 08-01-PLAN.md | E2E test: POST to `/v1/inbound/whatsapp` with valid Meta payload triggers W_IN_WHATSAPP_ADAPTER and creates a record in the inbound_messages table | SATISFIED | `scripts/test-n8n-e2e.sh` lines 81-107: Meta HMAC-SHA256 signed payload POST to `/webhook/v1/inbound/whatsapp`, 20s Postgres poll asserting `inbound_messages` row by `msg_id`; direct Postgres assertion, not Strapi HTTP |
| TEST-10 | 08-01-PLAN.md | E2E test: failed outbound message is retried with exponential backoff (verify Redis queue entry exists after first failure) | SATISFIED | `scripts/test-n8n-e2e.sh` lines 113-176: seeds `ralphe:outbox:pending` with `attempts=1,retryable=true`, triggers W15_OUTBOX_WORKER, verifies entry re-queued with `attempts >= 2`; `retryable:true` auto-fix applied (documented in 08-01-SUMMARY.md, deviation 1) |
| TEST-11 | 08-02-PLAN.md | Workflow smoke tests run in CI using n8n test mode or mock webhook triggers | SATISFIED | `ci.yml` job `n8n-workflow-e2e` runs on isolated ubuntu-latest runner with full inline compose stack (no live VPS required), imports and activates workflows, runs `test-n8n-e2e.sh`, tears down on completion or failure |

**Requirement coverage:** 3/3 (TEST-09, TEST-10, TEST-11) — all satisfied.

**Orphaned requirements check:** REQUIREMENTS.md Traceability table maps TEST-09, TEST-10, TEST-11 exclusively to Phase 8. No additional IDs from Phase 8 found in REQUIREMENTS.md that are unaccounted for.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | — | No anti-patterns detected | — | — |

Scanned `scripts/test-n8n-e2e.sh` for: TODO/FIXME/PLACEHOLDER, empty implementations (`return null`, `return {}`, `return []`), console-log-only handlers. None found.

Scanned `ci.yml` n8n-workflow-e2e job section (lines 838-1054) for: incomplete steps, placeholder commands, TODO comments. None found.

---

## Supply Chain Security

All GitHub Actions in the `n8n-workflow-e2e` job are SHA-pinned:
- `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683` (v4.2.2)
- `actions/upload-artifact@65462800fd760344b1a7b4382951275a0abb4808` (v4.6.0)

The existing `smoke-n8n-e2e` job (lines 754-774) is preserved unchanged (5 references in ci.yml confirmed, same as before).

No tab characters in ci.yml (YAML-safe).

---

## Notable Design Decisions Verified

1. **`META_APP_SECRET` defaults to `ci-test`** (not `test_meta_app_secret_for_e2e`) — matches `docker/docker-compose.test.yml` line 66 default. HMAC will match during CI execution without any additional env var injection.

2. **`retryable:true` field present in outbox seed entry** (line 129) — W15_OUTBOX_WORKER only re-queues to `ralphe:outbox:pending` when `retryable=true AND attempts < maxAttempts(7)`; missing this field would route entry to DLQ and TEST-10 would always FAIL. Applied as Rule 1 auto-fix in Phase 08-01 execution.

3. **`poll_for_record()` uses 20s async poll** — n8n queue mode returns HTTP 200 ACK before workflow execution; immediate DB assertion would always fail.

4. **CI job inlines full stack lifecycle** — `test_harness.sh` cannot be reused as a setup script because it calls `docker compose down -v` at step 8; each CI runner is isolated.

5. **Workflow activation via `UPDATE workflow_entity SET active = true`** — n8n 2.x `PATCH` activation returns `active=unknown` and is unreliable; DB direct update bypasses this.

---

## Human Verification Required

### 1. TEST-09 Full Execution Pass

**Test:** Start `docker/docker-compose.test.yml` stack with `docker compose up -d`, import and activate W1_IN_WA workflow, run `bash scripts/test-n8n-e2e.sh`
**Expected:** TEST-09 outputs `PASS: TEST-09: inbound_messages row created for msg_id=...`
**Why human:** n8n workflow execution against a live Postgres container cannot be verified statically. The script logic is correct, but the actual WA webhook path (`/webhook/v1/inbound/whatsapp`) and node execution in W1_IN_WA must be confirmed at runtime.

### 2. TEST-10 Full Execution Pass

**Test:** Same stack as above, with W15_OUTBOX_WORKER imported and activated, mock-api returning 500 on `/send/wa`
**Expected:** TEST-10 outputs `PASS: TEST-10: entry re-queued with attempts=2 (expected >= 2)`
**Why human:** Whether `POST /rest/workflows/:id/run` triggers W15 in n8n 2.9.4 queue mode, or whether the CRON trigger fires within 35s, depends on runtime n8n behaviour that cannot be verified statically.

### 3. CI Job Green on `main` Push

**Test:** Push a commit to `main` branch; observe GitHub Actions CI run
**Expected:** `n8n-workflow-e2e` job completes with status `success`; job appears in ci-summary table as `PASS`
**Why human:** CI runner environment (docker daemon availability, port 25678 binding, n8n 2.9.4 startup time on ubuntu-latest) can only be confirmed by a live run.

---

## Commit Provenance

| Artifact | Commit | Message |
|----------|--------|---------|
| `scripts/test-n8n-e2e.sh` | `ce9e174` | `feat(08-01): create scripts/test-n8n-e2e.sh with TEST-09 and TEST-10` |
| `.github/workflows/ci.yml` (n8n-workflow-e2e job) | `8780a67` | `fix(09-02): switch smoke-nginx-routing to burst-test script and run on PRs` (job was added here during Phase 09-02 execution, pre-existing when 08-02 ran) |

Note: The 08-02 SUMMARY acknowledges the job was "already fully present" when the plan was executed. Both commits exist and are verified in git log.

---

## Gaps Summary

None — all 6 must-have truths verified, all 3 requirement IDs (TEST-09, TEST-10, TEST-11) satisfied, both artifacts exist at correct line counts with substantive implementations, all key links wired. No blocker anti-patterns.

---

_Verified: 2026-03-30_
_Verifier: Claude (gsd-verifier)_
