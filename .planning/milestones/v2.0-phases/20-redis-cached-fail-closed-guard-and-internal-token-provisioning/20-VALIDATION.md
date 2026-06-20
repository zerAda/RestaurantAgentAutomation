---
phase: 20
slug: redis-cached-fail-closed-guard-and-internal-token-provisioning
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-20
---

# Phase 20 — Validation Strategy

> Per-phase validation contract. Detailed checks derive from `20-RESEARCH.md` → `## 7. Validation
> Architecture`. The keystone of this phase is a pair of **pure decision seams** —
> `scripts/guard/entitlement-decision.mjs` (cache-aside fail-closed logic) and
> `scripts/guard/classify-deny.mjs` (reason→severity) — authored as **plain ESM `.mjs`** (NOT `.ts`), so
> they are `node --test`-able in plain Node **without** `--experimental-strip-types` and **without booting
> n8n or Strapi**. The guard workflow itself is verified **structurally** with `jq`; the token wiring with
> `grep` + a `preflight.sh` negative test — all docker-free.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `node --test` (Node **22.22.2** at `/opt/node22/bin/node`) driving the two pure `.mjs` seams (no n8n/Strapi/Redis needed for the decision-logic tests — "HIT → 0 Strapi fetches" is a call-count assertion); `jq` (`/usr/bin/jq`) for STRUCTURAL assertions on `workflows/W0_MODULE_GUARD.json` (Redis GET/SET keyed, 0 Strapi nodes on the hit path, both Strapi httpRequest nodes on the miss path, TTLs); `redis-server`/`redis-cli` (`/usr/bin`, redis-server 7.0.15) for an OPTIONAL live SET→GET round-trip on the canonical key; `grep` + `bash` for the compose/env/secrets-inventory greps and the `preflight.sh` negative test; `python3 yaml.safe_load` for the compose + CI YAML |
| **Config file** | `.github/workflows/phase-20-assertions.yml` (new, Wave 0 — mirrors `phase-19-assertions.yml`; PIN `actions/setup-node@39370e3970a6d050c480ffad4ff0ed4d3fdee5af # v4.1.0` `node-version: '22'` in node-running jobs even though the seams are `.mjs` — for determinism/parity). 20-01 creates the structural-jq + guard-seam node-test jobs; 20-02 appends the ENT-03 grep/preflight-negative job; 20-03 appends the classifier node-test job |
| **Quick run command (structural, <5s)** | `jq -e '[.nodes[]\|select(.type=="n8n-nodes-base.redis")]\|length>=2' workflows/W0_MODULE_GUARD.json && grep -q "ralphe:entitlement:" workflows/W0_MODULE_GUARD.json && grep -q "STRAPI_API_TOKEN_INTERNAL" config/.env.example` |
| **Seam tests (local, <5s)** | `/opt/node22/bin/node --test scripts/guard/__tests__/entitlement-decision.test.mjs scripts/guard/__tests__/classify-deny.test.mjs` |
| **Full suite command (local, docker-free)** | `bash scripts/test-phase20.sh` (runs the seam node-tests + the jq structural checks on `W0_MODULE_GUARD.json` + the optional ephemeral-redis round-trip + the preflight negative test) |
| **Full suite command (CI)** | `act pull_request -W .github/workflows/phase-20-assertions.yml` (or push to PR) |
| **Estimated runtime** | <5s per-task local (`node --test` + jq/grep); ~5s local `scripts/test-phase20.sh`; ~60s CI (Node-22 setup + node-tests + jq + grep + preflight negative) |

### Local reality — NO docker (verified on this host 2026-06-20)

Docker daemon is **DOWN** on this host. Phase 20 needs NO ephemeral Postgres (unlike Phase 19) — the
decision logic is pure and the guard is verified structurally. The only runtime services are local Node
22 and an optional local Redis:

```bash
# 1. Pure decision seams (no services at all) — the load-bearing "HIT → 0 fetches" proof:
/opt/node22/bin/node --test \
  scripts/guard/__tests__/entitlement-decision.test.mjs \
  scripts/guard/__tests__/classify-deny.test.mjs

# 2. Structural jq on the guard workflow (Redis GET/SET keyed, 0 Strapi on hit, both Strapi on miss, TTLs):
jq -e '[.nodes[]|select(.type=="n8n-nodes-base.redis")|select(.parameters.key|test("ralphe:entitlement:"))]|length>=2' \
  workflows/W0_MODULE_GUARD.json
jq -e '[.nodes[]|select(.type=="n8n-nodes-base.httpRequest")]|length==2' workflows/W0_MODULE_GUARD.json

# 3. OPTIONAL ephemeral Redis live round-trip on the EXACT canonical key (binary at /usr/bin):
redis-server --port 7390 --daemonize yes --save "" --appendonly no --dir /tmp
redis-cli -p 7390 set "ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp" \
  '{"ent":{"enabled":true},"mod":{"tier":"addon"},"fetchedAt":"x"}' EX 300
redis-cli -p 7390 get "ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp"  # -> the row
redis-cli -p 7390 shutdown nosave

# 4. Preflight fail-fast negative test (the ENT-03 docker-free gate):
env -u STRAPI_API_TOKEN_INTERNAL -u STRAPI_API_URL bash scripts/preflight.sh; echo "exit=$?"  # -> non-zero + "❌ Missing env: STRAPI_API_TOKEN_INTERNAL"
```

`scripts/test-phase20.sh` (Plan 20-01) orchestrates 1+2+3; the preflight negative test (4) is exercised
by 20-02's CI job. Local runner is Node **22.22.2** + Redis **7.0.15** from `/usr/bin`; CI pins Node
**22** via `actions/setup-node@…v4.1.0` (prod parity: Redis 7). **No `.ts` type-stripping anywhere** — the
seams are `.mjs` (Phase-19 BLOCKER A sidestepped); Node 22 is pinned in CI only for determinism/parity.

---

## Sampling Rate

- **After every task commit:** for the seam changes, `/opt/node22/bin/node --test` on the changed `.mjs`
  + `node --check`; for `W0_MODULE_GUARD.json`, the jq structural checks; for the compose/env/preflight
  changes, `python3 yaml.safe_load` on the composes + `bash -n scripts/preflight.sh` + the preflight
  negative test.
- **After every plan wave:** full local suite (`bash scripts/test-phase20.sh`) + the appended ENT-03 and
  classifier jobs.
- **Before `/gsd:verify-work`:** full `phase-20-assertions.yml` green (structural jq + both seam
  node-tests + the ENT-03 grep/preflight job + the classifier job) AND `docs/guard-alert-split.md` recorded.
- **Max feedback latency:** ~60s (full CI suite); <5s per-task local jq/grep + `node --test`.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 20-01-01 | 01 | 1 | GRD-01 | node --test (pure seam, mock call-count) | `/opt/node22/bin/node --test scripts/guard/__tests__/entitlement-decision.test.mjs` — HIT→0 fetches, Redis-err→fallthrough, Strapi-err→DENY (not cached), expired re-eval, key byte-for-byte | ❌ W0 | ⬜ pending |
| 20-01-02 | 01 | 1 | GRD-01 | jq structural (guard JSON) | `W0_MODULE_GUARD.json`: ≥2 `n8n-nodes-base.redis` (GET+SET) keyed `ralphe:entitlement:`, exactly 2 Strapi httpRequest on miss, 0 on hit branch, SET has `ttl`, `GUARD_ERROR_FAILCLOSED` present, TTL envs read, no `ioredis`/`SCAN`/`KEYS` | ❌ W0 | ⬜ pending |
| 20-01-03 | 01 | 1 | GRD-01 | yaml + bash (harness + CI gate) | `python3 yaml.safe_load(phase-20-assertions.yml)`; pinned checkout + `setup-node@…v4.1.0` `node-version '22'`; `bash -n scripts/test-phase20.sh` boots optional ephemeral redis + runs the seam test + jq | ❌ W0 | ⬜ pending |
| 20-02-01 | 02 | 1 | ENT-03 | yaml + grep (compose) | both composes parse; prod token HARD `${VAR:?}` x2 n8n services, base token SOFT `${VAR:-}` x2; `STRAPI_API_URL` + `ENTITLEMENT_CACHE_TTL_SEC`/`_NEG_` present in both | ✅ (files exist) | ⬜ pending |
| 20-02-02 | 02 | 1 | ENT-03 | grep + bash negative (env/inventory/preflight) | token in `.env.example` (tobemodified/[SECRET]) + annotated in secrets inventory; `env -u STRAPI_API_TOKEN_INTERNAL bash scripts/preflight.sh` exits non-zero with a token-mentioning message | ✅ (files exist) | ⬜ pending |
| 20-02-03 | 02 | 1 | ENT-03 | yaml / CI gate (append) | `ent03-token-wiring` job appended to `phase-20-assertions.yml` (20-01 jobs intact): compose×2 + `.env.example` + inventory greps + the `env -u …` preflight negative test | ❌ W0 (20-01 creates the file) | ⬜ pending |
| 20-03-01 | 03 | 1 | GRD-01 | node --test (pure classifier) | `/opt/node22/bin/node --test scripts/guard/__tests__/classify-deny.test.mjs` — FAILCLOSED→pageable HIGH, NO_ENTITLEMENT→non-pageable LOW, unknown→pageable HIGH safe default | ❌ W0 | ⬜ pending |
| 20-03-02 | 03 | 1 | GRD-01 | grep + yaml (doc + CI append) | `docs/guard-alert-split.md` records the severity contract + the `security_events`/`ALERT_WEBHOOK_URL` wiring (guard UNCHANGED — O-3); `guard-alert-classifier` job appended (20-01/20-02 jobs intact) | ❌ W0 (20-01 creates the file) | ⬜ pending |

*Wave-0 artifacts (the two `.mjs` seams + their tests, `W0_MODULE_GUARD.json`, `scripts/test-phase20.sh`,
`phase-20-assertions.yml`) are themselves the validation infrastructure. All three plans are Wave 1 and
parallel-safe on file ownership — but the two appender tasks (20-02-03, 20-03-02) WRITE into the
`phase-20-assertions.yml` that 20-01 CREATES. To keep ownership clean and avoid a write-conflict, the
executor sequences 20-01 first within Wave 1 (the file-creator), then 20-02 and 20-03 APPEND their jobs.
This is a same-file append ordering, not a logical dependency — see "Wave / ordering note" below.*

---

## Wave 0 Requirements

- [ ] `scripts/guard/entitlement-decision.mjs` — the pure cache-aside decision seam (Plan 20-01 Task 1)
- [ ] `scripts/guard/__tests__/entitlement-decision.test.mjs` — `node --test` proving HIT→0 fetches / Redis-err→fallthrough / Strapi-err→DENY / expired re-eval / key byte-for-byte (Plan 20-01 Task 1)
- [ ] `workflows/W0_MODULE_GUARD.json` — the Redis cache-aside restructure (Plan 20-01 Task 2; the SOLE editor)
- [ ] `scripts/guard/classify-deny.mjs` + `scripts/guard/__tests__/classify-deny.test.mjs` — the reason→severity classifier + test (Plan 20-03 Task 1)
- [ ] `scripts/test-phase20.sh` — local docker-free harness (seam node-tests + jq structural + optional ephemeral redis) (Plan 20-01 Task 3)
- [ ] `.github/workflows/phase-20-assertions.yml` — CI gate; 20-01 creates (structural jq + guard-seam node-test, pinned Node 22), 20-02 appends the ENT-03 job, 20-03 appends the classifier job (Plans 20-01/02/03)
- [ ] `docs/guard-alert-split.md` — the severity contract + the downstream alert wiring (Plan 20-03 Task 2)

*(No framework install — `node --test`, `jq`, `redis-server`/`redis-cli`, `grep`, `bash`, `python3` all
present on the host at `/opt/node22/bin` & `/usr/bin`.)*

---

## Wave / ordering note

All three plans are **Wave 1** (`wave: 1`, `depends_on: []`) — disjoint on their OWNED files:

| Plan | Owned files (disjoint) |
|------|------------------------|
| 20-01 | `scripts/guard/entitlement-decision.mjs` (+ test), **`workflows/W0_MODULE_GUARD.json` — SOLE editor**, `scripts/test-phase20.sh`, **creates** `.github/workflows/phase-20-assertions.yml` |
| 20-02 | `docker-compose.hostinger.prod.yml`, `docker-compose.base.yml`, `config/.env.example`, `docs/SECRETS_ROTATION_REQUIRED.md`, `scripts/preflight.sh`, **appends to** `phase-20-assertions.yml` |
| 20-03 | `scripts/guard/classify-deny.mjs` (+ test), `docs/guard-alert-split.md`, **appends to** `phase-20-assertions.yml` |

The ONLY shared file is `.github/workflows/phase-20-assertions.yml`: 20-01 **creates** it; 20-02 and
20-03 **append** their own jobs. The executor runs 20-01 first within the wave (the file-creator), then
20-02/20-03 append — a file-creation-before-append ordering, NOT a behavioral dependency (each plan's
logic is independent and individually testable). `W0_MODULE_GUARD.json` is touched by 20-01 ONLY (20-03
references it read-only via a CI grep; 20-02 never touches any workflow). No two plans WRITE the same
non-CI file.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 🔴 Import the restructured `W0_MODULE_GUARD.json` on the prod n8n (re-wires the `REDIS_CREDENTIAL_ID` placeholder to the live `43SDqJYMGa6RvFqW` Redis credential) | GRD-01 | Requires the prod n8n editor / CLI import + the live credential | Deferred to a prod-connected session: import the workflow, confirm the Redis nodes bind to the live credential, send a test inbound and confirm a HIT skips the Strapi calls |
| 🔴 Provision the real `STRAPI_API_TOKEN_INTERNAL` value (a Strapi-admin-generated internal API token) into the prod env + confirm `STRAPI_API_URL=http://strapi:1337` | ENT-03 | Requires the Strapi admin panel on the VPS + the prod `.env`; the hard `${VAR:?}` means prod n8n won't start until it exists (the desired guarantee) | Deferred: generate the token in Strapi admin, set it in the prod `.env`, run `scripts/preflight.sh` (must pass), then `docker compose up` |
| 🔴 Set the Redis credential id on prod + confirm the guard's GET/SET Redis is the SAME Redis the Phase-19 `DEL` (`audit-hook.ts:122`) targets (else revocation won't evict the live cache) | GRD-01 | Requires the prod Redis + the Phase-19 hook wiring | Deferred: confirm `REDIS_CREDENTIAL_ID`/`QUEUE_BULL_REDIS_HOST=redis` resolve to the same instance; SET a key via the guard, then trigger a Phase-19 entitlement change and confirm the DEL evicts it |
| 🔴 Confirm the prod Redis `maxmemory-policy` (`allkeys-lru` per the criterion) | GRD-01 | Requires the prod Redis config | Deferred: `redis-cli CONFIG GET maxmemory-policy`; the cache-aside topology is correct regardless (a miss → live query, never a deny), but document the assumption |
| 🔴 Wire the alert split into the live caller deny-branch / `W8_OPS` (`security_events.severity` from `classify().severity` + the `ALERT_WEBHOOK_URL` fan-out on `classify().pageable`) and import | GRD-01 (crit 4) | Requires the prod n8n workflow edits + import; `docs/guard-alert-split.md` specifies the wiring but the live edit is import-time | Deferred to a prod-connected session per `docs/guard-alert-split.md` |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (every task carries one)
- [x] Wave 0 covers all MISSING references (the two `.mjs` seams + tests, `W0_MODULE_GUARD.json`, `scripts/test-phase20.sh`, `phase-20-assertions.yml`, `docs/guard-alert-split.md`)
- [x] No watch-mode flags
- [x] Feedback latency < 100s (full suite); <5s per-task local jq/grep + `node --test`
- [x] No `SAVEPOINT` in any DO block (N/A — Phase 20 has no SQL)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planned (3 plans — disjoint file ownership, all Wave 1. 20-01 owns the pure decision seam +
**the SOLE edit of `W0_MODULE_GUARD.json`** + the harness + the CI-gate CREATION; 20-02 owns the
compose/env/secrets-inventory/preflight token wiring (NO workflow edits) + appends the ENT-03 CI job;
20-03 owns the pure classifier + the alert-split doc (downstream-only — does NOT edit the guard, O-3) +
appends the classifier CI job. The only shared file is `phase-20-assertions.yml`: created by 20-01,
appended by 20-02/20-03 in that order. No two plans WRITE the same non-CI file.)
