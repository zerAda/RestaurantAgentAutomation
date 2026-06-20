---
phase: 20-redis-cached-fail-closed-guard-and-internal-token-provisioning
verified: 2026-06-20T18:53:30Z
status: passed
score: 4/4 success criteria verified (code/CI level; HIT-path graph-reachability = 0 httpRequest; 31/31 node tests; prod-HARD/base-SOFT + negative-preflight confirmed; integrity gate exit 0; cache-key byte-identical across guard JSON + .mjs + Phase-19 DEL + ADR 0003; live workflow import / real token value / live alert wiring / allkeys-lru confirmation deferred)
gaps: []
requirements_satisfied: [GRD-01, ENT-03]
deferred_to_vps:
  - "Import the restructured workflows/W0_MODULE_GUARD.json onto prod n8n — this wires the placeholder REDIS_CREDENTIAL_ID to the live Redis credential (43SDqJYMGa6RvFqW) and is the only path that activates the cache-aside topology in production (legitimate: code/CI verifies topology+keys+TTLs+graph-reachability; only the import binds the live credential id)"
  - "Confirm the guard's Redis (the GET/SET target) is the SAME Redis the Phase-19 audit-hook.ts DEL targets — else a revocation won't invalidate the live cache (cache-key is already byte-identical in code; only the live REDIS_URL/credential identity needs confirming on prod)"
  - "Confirm the prod Redis maxmemory-policy is allkeys-lru — the seam already proves an LRU-eviction miss -> live query -> never a spurious deny (node test 'LRU eviction (miss) -> live query'), but the live eviction policy is a VPS runtime setting"
  - "Provision the REAL STRAPI_API_TOKEN_INTERNAL value (a Strapi-admin-generated internal API token) into the prod env; the hard ${VAR:?} on both n8n services guarantees prod n8n refuses to start until it exists (code/CI verifies the declaration + preflight fail-fast; only the secret VALUE is deferred)"
  - "Execute the live edit to the caller deny-branch (W1_IN_WA B0 - Log Deny: security_events.severity from classify(reason).severity instead of hardcoded 'HIGH' at W1_IN_WA.json:240) + the W8_OPS pageable fan-out to ALERT_WEBHOOK_URL, then import the updated workflows — documented in docs/guard-alert-split.md (legitimate: the pure classify() seam + the wiring contract ship and are tested at code/CI; only the live workflow edit is VPS-deferred, NOT an unmet criterion)"
---

# Phase 20: Redis-Cached Fail-Closed Guard + Internal Token Provisioning — Verification

**Goal:** `W0_MODULE_GUARD` caches module/entitlement lookups in Redis so a cache HIT skips both Strapi round-trips per inbound message (still fail-closed on error), and `STRAPI_API_TOKEN_INTERNAL` is a first-class, preflight-checked secret so a missing secret can no longer become a total inbound/operator lockout.
**Status:** passed — 4/4 ROADMAP success criteria met at the code/CI level. The HIT-path graph-reachability invariant (0 Strapi httpRequest reachable on hit) was independently re-derived from the n8n connections graph; the full guard seam + classifier node suites (31/31), every CI structural jq assertion, the prod-HARD/base-SOFT token wiring, the negative-preflight fail-fast, the integrity gate (exit 0), and an ephemeral-Redis round-trip on the canonical key were all independently reproduced. The live workflow import / real token value / live alert-branch edit / prod-Redis identity / allkeys-lru confirmation are legitimately deferred to a prod-connected session.

## Observable Truths

| # | Success Criterion | Status | Evidence |
|---|-------------------|--------|----------|
| 1 | `W0_MODULE_GUARD.json` cache-aside keyed EXACTLY `ralphe:entitlement:<tenant_id>:<module_key>` (positive TTL 300 / negative 60); a HIT skips BOTH Strapi fetches (0 httpRequest reachable from the IF HIT branch); exactly 2 Strapi httpRequest on the miss branch | VERIFIED | **Independent graph walk** from `connections["IF - Cache Usable?"].main[0]` (HIT seed = `["Return Cached Decision"]`, a terminal Code node with no outgoing edge): **HIT-reachable httpRequest nodes = 0** (re-ran the CI jq verbatim — PASS). Both Redis nodes keyed `=ralphe:entitlement:{{$json.tenant_id}}:{{$json.module_key}}` (GET line 33, SET line 202); SET has `expire:true`, `ttl:={{ $json._cacheTtl }}`. **Total httpRequest = 2** (`Strapi - GET product-modules`, `Strapi - GET tenant-entitlements`), both reachable only via the MISS branch `main[1]`. Evaluate node reads `ENTITLEMENT_CACHE_TTL_SEC` (pos, default 300) / `ENTITLEMENT_NEG_CACHE_TTL_SEC` (neg, default 60). Guard-input-validate deny carries `_cacheUsable:false` (×2) AND `_cacheable:false` (×2) so it terminates as a deny with no spurious read/write. JSON valid (`json.load` OK). |
| 2 | The 4 correctness pivots correct AND tested in `entitlement-decision.mjs`: (a) raw row + fetchedAt → expiry re-evaluated on read; (b) guard/Strapi error → SET skipped; (c) Redis error → fall through; (d) Strapi error → DENY (fail-closed); + HIT → 0 fetches, LRU miss → live query | VERIFIED | `decideFromCache` re-runs `isExpired(ent, now)` on the stored `{ent,mod,fetchedAt}` raw row (a); `evaluateLive` returns `cacheable:false, ttl:0` on any `strapiError` so the IF-Cacheable FALSE branch skips the SET (b); a Redis `{error}` envelope / nil / unparseable → `cacheUsable:false` = MISS, never a deny (c); Strapi error → `GUARD_ERROR_FAILCLOSED…` DENY (d). **Independent `node --test` (20 tests) all PASS**, including: `strapiCalls===0` on HIT (explicit `assert.equal(strapiCalls===0, true)`), expired-row re-eval → `EXPIRED`, `{error}`→FAILCLOSED `cacheable:false ttl:0`, 401/non-2xx→FAILCLOSED (NOT NO_ENTITLEMENT), Redis-error/nil→MISS, `LRU eviction (miss) -> live query, never spurious deny`, TTL 300/60 + injectable overrides. |
| 3 | `STRAPI_API_TOKEN_INTERNAL` declared HARD `${VAR:?}` (both n8n services, prod) + SOFT `${VAR:-}` (base, NOT hard) + `.env.example` + `SECRETS_ROTATION_REQUIRED.md`; `preflight.sh` fails fast (clear msg, non-zero) when unset; TTL envs 300/60 declared | VERIFIED | **prod** (`docker-compose.hostinger.prod.yml`): HARD `${STRAPI_API_TOKEN_INTERNAL:?…lockout}` on `n8n-main` (L403) AND `n8n-worker` (L553) + `STRAPI_API_URL` + `ENTITLEMENT_CACHE_TTL_SEC=300` / `ENTITLEMENT_NEG_CACHE_TTL_SEC=60` in both blocks. **base** (`docker-compose.base.yml`): SOFT `${STRAPI_API_TOKEN_INTERNAL:-}` on both n8n services (L319, L378) — `grep STRAPI_API_TOKEN_INTERNAL:?` finds NOTHING in base (so dev/CI `compose config` stays green). `.env.example` L580 `STRAPI_API_TOKEN_INTERNAL=tobemodified  # [SECRET]` + URL + TTLs (L579/581/582). `SECRETS_ROTATION_REQUIRED.md` L23/25/28 annotate it as the W0_MODULE_GUARD token whose absence = total lockout. `preflight.sh` REQ_VARS includes the token (L12). **Negative test** `env -u STRAPI_API_TOKEN_INTERNAL bash scripts/preflight.sh` → `❌ Missing env: STRAPI_API_TOKEN_INTERNAL`, exit **1**; with it set, that line is gone. All three YAMLs `yaml.safe_load` OK. |
| 4 | `GUARD_ERROR_FAILCLOSED*` distinguishable from `NO_ENTITLEMENT`/`MODULE_NOT_FOUND`/`EXPIRED` via tested `classify-deny.mjs` (pageable/HIGH vs non-pageable/LOW; unknown→pageable safe default); `guard-alert-split.md` documents the wiring; only the LIVE workflow edit is 🔴 VPS-deferred (deferral legitimate) | VERIFIED | `classify()`: `GUARD_ERROR_FAILCLOSED*`→`{cannot-determine, HIGH, pageable:true, GUARD_FAILCLOSED}`; `NO_ENTITLEMENT*`/`MODULE_NOT_FOUND*`/`EXPIRED*`→`{denial, LOW, pageable:false, null}`; `GUARD_ERROR:`→`{caller-bug, MEDIUM, false}` (FAILCLOSED matched BEFORE generic `GUARD_ERROR:` so the outage isn't shadowed); unknown/`''`/null/undefined→`{unknown, HIGH, pageable:true, GUARD_UNKNOWN}`. **Independent `node --test` (11 tests) all PASS**, incl. the core distinction `FAILCLOSED.pageable===true && NO_ENTITLEMENT.pageable===false`, the not-shadowed case, and unknown→HIGH-no-throw. `docs/guard-alert-split.md` documents the severity contract + EXACT downstream wiring (`security_events.severity` at `W1_IN_WA.json:240`; `W8_OPS` `E4 - Optional Alert Webhook` `ALERT_WEBHOOK_URL`) with the guard topology unchanged. **O-3 confirmed via git**: the 20-03 commits (`b3985f3`,`7d546f6`,`2060a91`) never touch `W0_MODULE_GUARD.json` (last modified only by the 20-01 commit `9163936`). The live deny-branch edit is the ONLY VPS deferral here — legitimate, not an unmet criterion. |

**Score: 4/4 success criteria verified.**

## Local Verification

| Check | Command (independent re-run) | Result |
|-------|------------------------------|--------|
| Guard seam node tests | `/opt/node22/bin/node --test scripts/guard/__tests__/entitlement-decision.test.mjs` | **20 pass / 0 fail** (incl. `strapiCalls===0` on HIT + pivots a–d) |
| Classifier node tests | `…/__tests__/classify-deny.test.mjs` | **11 pass / 0 fail** (FAILCLOSED pageable vs NO_ENTITLEMENT not; unknown→HIGH) |
| All guard tests (combined) | `node --test scripts/guard/__tests__/*.mjs` | **tests 31 / pass 31 / fail 0 / skipped 0** |
| **HIT-path graph reachability** | CI jq walked from `IF - Cache Usable?` `main[0]` | **httpRequest reachable on HIT = 0** (PASS) |
| Strapi node count | `jq '[.nodes[]\|select(.type=="n8n-nodes-base.httpRequest")]\|length'` | **2** (product-modules + tenant-entitlements, miss branch only) |
| Redis GET/SET keys + ttl + cred | CI structural jq | PASS (both keyed `ralphe:entitlement:…`, SET ttl present, `REDIS_CREDENTIAL_ID` placeholder) |
| FAILCLOSED + TTL envs / no ioredis·SCAN·KEYS | CI structural grep | PASS |
| prod HARD `:?` (both n8n) / base NOT hard | CI `grep -E STRAPI_API_TOKEN_INTERNAL:\?` | PASS prod / PASS base-not-hard |
| Negative preflight | `env -u STRAPI_API_TOKEN_INTERNAL bash scripts/preflight.sh` | **exit 1**, `❌ Missing env: STRAPI_API_TOKEN_INTERNAL` |
| Positive preflight (token check) | token set | token line absent (passes that check) |
| YAML valid | `yaml.safe_load` on phase-20-assertions.yml + both composes | all OK |
| JSON valid | `json.load` on W0_MODULE_GUARD.json | OK |
| Integrity gate | `bash scripts/integrity_gate.sh` | **exit 0** (✅ Integrity Gate PASS) |
| Harness end-to-end | `bash scripts/test-phase20.sh` | **exit 0** — classifier green, structural+graph-reachability green, ephemeral-Redis SET→GET round-trip green |
| **Cache-key byte-identity** | grep across 4 sources | **IDENTICAL**: `audit-hook.ts:122` (Phase-19 DEL) `` `ralphe:entitlement:${tenant_id}:${module_key}` `` = `entitlement-decision.mjs:34` `buildCacheKey` = W0 GET (L33) = W0 SET (L202) `ralphe:entitlement:{{$json.tenant_id}}:{{$json.module_key}}`; ADR 0003 locks the same contract |

**Tooling:** `/opt/node22/bin/node` v22.22.2; `redis-server`/`redis-cli` at `/usr/bin` (harness ephemeral round-trip used). `docker compose config` not runnable in the sandbox (Docker absent), but base uses only SOFT `:-` forms (no `:?`) so dev/CI `compose config` stays green — verified structurally + by YAML parse.

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `workflows/W0_MODULE_GUARD.json` | 12-node Redis cache-aside; GET/SET on canonical key; IF HIT→cached, MISS→2 Strapi httpRequest; IF-Cacheable gates the SET | VERIFIED | Topology + connections re-walked; 0 httpRequest on HIT; 2 on miss; SET skipped on error/input-error path; TTL envs read; emits `GUARD_ERROR_FAILCLOSED`/`NO_ENTITLEMENT`/`MODULE_NOT_FOUND`/`EXPIRED` |
| `scripts/guard/entitlement-decision.mjs` | pure seam: buildCacheKey + decideFromCache (re-eval expiry) + evaluateLive (fail-closed, cacheable+ttl) | VERIFIED | 297 lines, 3 exports, zero n8n/Strapi/Redis import; pivots a–d encoded |
| `scripts/guard/__tests__/entitlement-decision.test.mjs` | node --test: HIT→0 fetches, Redis-err→fallthrough, Strapi-err→DENY, expired re-eval, key byte-for-byte, TTL 300/60 | VERIFIED | 20 tests, all PASS independently |
| `scripts/guard/classify-deny.mjs` | pure reason→{class,severity,pageable,alertKey}; FAILCLOSED before GUARD_ERROR:; unknown→pageable HIGH | VERIFIED | 59 lines, 1 export, zero n8n/Strapi import |
| `scripts/guard/__tests__/classify-deny.test.mjs` | node --test: every prefix + FAILCLOSED-pages/NO_ENTITLEMENT-doesn't + unknown→HIGH | VERIFIED | 11 tests, all PASS independently |
| `docker-compose.hostinger.prod.yml` | HARD `${VAR:?}` token (both n8n) + URL + TTLs | VERIFIED | L403/L553 hard; L402/L404/L405 + L552/L554/L555 URL+TTLs; YAML OK |
| `docker-compose.base.yml` | SOFT `${VAR:-}` token (NOT hard) + URL + TTLs | VERIFIED | L319/L378 soft; no `:?`; URL+TTLs both blocks; YAML OK |
| `config/.env.example` | token (`tobemodified` / `[SECRET]`) + URL + TTL envs | VERIFIED | L580 token, L579 URL, L581/582 TTLs |
| `docs/SECRETS_ROTATION_REQUIRED.md` | token annotated as the guard internal token / lockout risk | VERIFIED | L23/25/28 |
| `scripts/preflight.sh` | REQ_VARS fail-fast on the token; clear message, exit 1 | VERIFIED | L12 in REQ_VARS; negative test exit 1 with `❌ Missing env: STRAPI_API_TOKEN_INTERNAL` |
| `.github/workflows/phase-20-assertions.yml` | 4 jobs (guard-decision-node-test, guard-structural incl. graph-reachability, ent03-token-wiring, guard-alert-classifier); Node 22 + SHA-pinned actions | VERIFIED | YAML OK; all 4 jobs present; pinned checkout@v4.2.2 / setup-node@v4.1.0 node 22; every structural jq re-run locally PASS |
| `scripts/test-phase20.sh` | docker-free harness: node-test + jq structural + graph-reachability + optional ephemeral-redis | VERIFIED | exit 0; ephemeral Redis round-trip on canonical key green |
| `docs/guard-alert-split.md` | severity contract + downstream wiring (security_events.severity + W8_OPS ALERT_WEBHOOK_URL); guard topology unchanged | VERIFIED | full contract table + exact wiring points + 🔴 VPS deferral + contract-stability note |
| `docs/adr/0003-…placement.md` | locks the cache-key contract `ralphe:entitlement:{tenant_id}:{module_key}` | VERIFIED | L67/71/79/187 record the locked Phase-20 GRD-01 cache-aside key |

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| GRD-01 | 20-01, 20-03 | `W0_MODULE_GUARD.json` caches lookups in Redis (≈5-min TTL, keyed `tenant_id:module_key`) so a HIT skips both Strapi round-trips; miss falls back to Strapi and still fails closed on error | SATISFIED | Truths 1+2+4; graph-proven 0 httpRequest on HIT; 31/31 node tests; FAILCLOSED never NO_ENTITLEMENT; classifier pages the outage |
| ENT-03 | 20-02 | `STRAPI_API_TOKEN_INTERNAL` a first-class secret (prod/base compose + .env.example + secrets inventory); preflight fails fast with a clear message if unset | SATISFIED | Truth 3; prod-HARD (both n8n) / base-SOFT; .env.example + inventory; negative preflight exit 1 with named token |

## Anti-Patterns Scanned

No blocker anti-patterns. The Code-node bodies are substantive (full decision ladders, not placeholders); no `TODO`/`FIXME`/`PLACEHOLDER` in the shipped guard/seam/classifier logic. The CI gate explicitly forbids and re-checks `ioredis`/`.scan(`/`KEYS `/`NODE_FUNCTION_ALLOW_EXTERNAL` in the guard JSON (PASS — none present). `REDIS_CREDENTIAL_ID` is an intentional import-time placeholder bound on VPS (tracked under deferred_to_vps), not a stub gap. `tobemodified` in `.env.example` is the documented gitleaks-allowlisted secret placeholder, not a committed secret.

## Deferred to VPS (legitimate — not gaps)

These are runtime/prod-connected steps the phase intentionally designs but does not execute; each underlying code/CI contract is verified above:
1. **Import `W0_MODULE_GUARD.json` on prod n8n** — binds the `REDIS_CREDENTIAL_ID` placeholder to the live Redis credential (`43SDqJYMGa6RvFqW`); the topology/keys/TTLs/graph-reachability are all code/CI-verified.
2. **Confirm guard-Redis == Phase-19-DEL-Redis** — cache-key is already byte-identical in code; only the live `REDIS_URL`/credential identity needs confirming so revocation invalidates the live cache.
3. **Confirm prod `allkeys-lru` maxmemory-policy** — the seam already proves LRU-miss → live query → never a spurious deny (node test); the eviction policy is a VPS runtime setting.
4. **Provision the real `STRAPI_API_TOKEN_INTERNAL` value** — prod's hard `${VAR:?}` (both n8n services) refuses startup until it exists; only the secret VALUE is deferred.
5. **Live alert wiring** — the caller deny-branch `security_events.severity = classify(reason).severity` (replacing the hardcoded `'HIGH'` at `W1_IN_WA.json:240`) + the `W8_OPS` `pageable` fan-out to `ALERT_WEBHOOK_URL`, then importing the updated workflows. The pure `classify()` seam + the wiring contract (`docs/guard-alert-split.md`) ship and are tested at code/CI; only the live workflow edit is deferred (O-3 — 20-03 never touches the guard JSON, git-confirmed).

## Verdict

**PASSED** — 4/4 ROADMAP success criteria met at the code/CI level; **no gaps**. Independent re-verification confirms: the HIT-path graph-reachability invariant holds (**0 Strapi httpRequest reachable on hit**), the full guard + classifier suites are green (**31/31, 0 fail**), the prod-HARD / base-SOFT token wiring + the negative-preflight fail-fast behave as specified, the integrity gate exits 0, and the cache key is byte-identical across the guard JSON, the `.mjs` seam, the Phase-19 DEL side, and ADR 0003. GRD-01 and ENT-03 are satisfied. The listed VPS items (workflow import / real token value / live alert-branch edit / prod-Redis identity / allkeys-lru confirmation) are legitimately deferred to a prod-connected session, not unmet criteria.

---
_Verified: 2026-06-20T18:53:30Z_
_Verifier: Claude (gsd-verifier)_
