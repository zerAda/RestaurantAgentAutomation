# Phase 20: Redis-Cached Fail-Closed Guard + Internal Token Provisioning — Research

**Researched:** 2026-06-20
**Domain:** n8n 2.9.4 **queue-mode** workflow restructuring of `W0_MODULE_GUARD.json` into a Redis **cache-aside** read/populate path (mirroring the repo's existing `W0_CONFIG_READER` Redis-GET → Code → IF → Strapi-fetch → Redis-SET topology) on the LOCKED `ralphe:entitlement:{tenant_id}:{module_key}` key (Phase-19 DEL side) + first-class `STRAPI_API_TOKEN_INTERNAL` secret wiring (compose/env/secrets-inventory + a startup preflight fail-fast) + a `GUARD_ERROR_FAILCLOSED` vs `NO_ENTITLEMENT` alert-severity split
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GRD-01 | `W0_MODULE_GUARD.json` caches module/entitlement lookups in Redis (≈5-min TTL, keyed `tenant_id:module_key`) so a cache **hit skips both** synchronous Strapi round-trips per inbound message; cache miss falls back to Strapi and still **fails closed on error**. | §1 (THE Redis-access mechanism — Redis nodes, NOT Code-node `require`, because `NODE_FUNCTION_ALLOW_EXTERNAL` is unset repo-wide), §2 (concrete node topology mirroring `W0_CONFIG_READER`), §3 (cache-key contract + TTLs, locked by Phase 19 / ADR 0003), §4 (fail-closed/fall-through/expiry-re-eval/LRU-eviction decision matrix), §7 (the pure decision-seam test proving "0 Strapi fetches on hit") |
| ENT-03 | `STRAPI_API_TOKEN_INTERNAL` is a first-class secret — declared in `docker-compose.hostinger.prod.yml`/`base`, `config/.env.example`, the secrets inventory — and a startup/preflight check fails fast (clear message) if unset, so the fail-closed guard can't turn a missing secret into a total inbound/operator lockout. | §5 (the exact gap: token is in NEITHER compose's n8n env NOR `.env.example`; the secrets inventory `docs/SECRETS_ROTATION_REQUIRED.md:23` already lists it), §5 (compose `${VAR:?message}` fail-fast precedent + the `scripts/preflight*.sh` extension point), §6 (alert split so a missing token is pageable) |
</phase_requirements>

---

## Summary

**THE central unknown is resolved by a single repo fact: `NODE_FUNCTION_ALLOW_EXTERNAL` is set NOWHERE in the repo** (grepped across every `*.yml`/`*.yaml`/`*.json`/`*.sh`/`*.env*` — zero hits), and **no Code node anywhere does `require('ioredis')`/`require('redis')`** (zero hits). The repo's *entire* Redis access pattern from n8n is the first-class **`n8n-nodes-base.redis`** node (21 workflows use it), reading/writing via a shared `redis` credential. Therefore the guard does **NOT** reach Redis from inside the sandboxed Code node — it must use **Redis GET/SET nodes wired around** the Code node. The repo even ships the exact cache-aside template to copy: **`W0_CONFIG_READER.json`** does `Trigger → Redis GET (continueOnFail) → "Cache Hit?" Code → IF branch → [hit: Return Cached] / [miss: Strapi fetch → Strapi fetch → Merge → Redis SET (expire+ttl) → Return Fresh]`. Phase 20's guard is that same shape with the entitlement key and the fail-closed decision folded into the "Cache Hit?"/decision Code node. **Decided topology (THE answer):** `Start → Redis GET ralphe:entitlement:{tenant}:{module} (continueOnFail) → "Guard Decide (cached?)" Code → IF (cacheUsable?) → [HIT path: "Return Cached Decision" — ZERO Strapi calls] / [MISS/Redis-error path: Strapi product-modules fetch → Strapi tenant-entitlements fetch → "Guard Evaluate (live)" Code (fail-closed on Strapi error) → IF (cacheable?) → Redis SET (expire+ttl) → Return] `. (Full node list in §2.)

**The cache-key, TTL, and the Phase-19 coupling are already LOCKED — Phase 20 is the POPULATE/READ half of a contract Phase 19 shipped.** `inventory-cms/.../tenant-entitlement/audit-hook.ts:122` does `DEL ralphe:entitlement:${tenant_id}:${module_key}` and ADR 0003 (Decision 2, `docs/adr/0003-entitlement-audit-placement.md:62-79`) locks the key **byte-for-byte** to `ralphe:entitlement:{tenant_id}:{module_key}` citing ROADMAP:147, and Decision 3 commits the ≤5-min positive TTL as the staleness bound for product-module changes. Phase 20's `GET`/`SET` MUST use that identical key or revocation (Phase-19 DEL) won't evict the live cache — the precise AUD-02/GRD-01 regression. The `ralphe:` prefix is the established key-space (`ralphe:dedupe:`, `ralphe:replay:`, `ralphe:outbox:`, `ralphe:quarantine:` all seen in workflows). **What Phase 20 newly decides:** the **TTL values** (recommend ~300s positive / ~30–60s negative), **what is cached** (the *raw entitlement row + a fetched-at stamp + a tier flag* — NOT the boolean decision, so expiry can be re-evaluated on read per criterion 2), and the **negative-cache** of `NO_ENTITLEMENT` at a shorter TTL with the rule that **transient `GUARD_ERROR_FAILCLOSED` is NEVER cached** (criterion 2).

**The ENT-03 gap is concrete and currently a live foot-gun:** the guard reads `$env.STRAPI_API_URL` and `$env.STRAPI_API_TOKEN_INTERNAL` (`W0_MODULE_GUARD.json:30-31`) but **NEITHER var is wired into the n8n-main or n8n-worker `environment:` block in `docker-compose.hostinger.prod.yml` OR `docker-compose.base.yml`** (grep-confirmed — only `STRAPI_SUPER_ADMIN_*` exist there), and **`STRAPI_API_TOKEN_INTERNAL` is absent from `config/.env.example`** (only `STRAPI_API_TOKEN_SALT` at line 570). The **secrets inventory** (`docs/SECRETS_ROTATION_REQUIRED.md:23`) already *lists* it (P1). So today a missing/unset token means the guard's `fetch()` 401s → `catch` → `GUARD_ERROR_FAILCLOSED` → **every inbound message and operator action denied, silently** — the exact total-lockout ENT-03 exists to prevent. The fix: declare the var in both compose n8n services (using the established `${VAR:?...}` fail-fast precedent at `docker-compose.hostinger.prod.yml:94-101`), add it to `.env.example`, and a **startup preflight** (extend the existing `scripts/preflight.sh` `REQ_VARS` array + a CI assertion) that exits non-zero with a clear message when unset. **Primary recommendation:** ship 3 plans with disjoint file ownership — **20-01** the workflow restructure (the ONLY plan that touches `W0_MODULE_GUARD.json`), **20-02** the token wiring + preflight (compose/env/secrets-doc/preflight script — NO workflow edits), **20-03** the alert split (`security_events`/`W8_OPS` severity mapping + the guard's reason-prefix contract — touches the alert wiring + a small reason-classifier seam, NOT the guard topology). The hard correctness lives in a **pure, Strapi-free, n8n-free decision seam** (`scripts/guard/entitlement-decision.mjs`) unit-tested with `node --test` proving "cache hit → 0 fetch calls", mirroring Phase 19's `audit-hook.ts` testable-seam discipline.

---

## 1. THE Redis-access mechanism for the guard (the central unknown — RESOLVED)

**Question:** In n8n 2.9.4 queue mode, how does `W0_MODULE_GUARD` reach Redis — a Code-node direct `ioredis` client, or `n8n-nodes-base.redis` nodes?

**Answer: `n8n-nodes-base.redis` nodes wired AROUND the Code node. The Code-node-direct-client option is NOT available in this repo and MUST NOT be introduced.**

Evidence (all grep-verified 2026-06-20):

| Probe | Result | Implication |
|-------|--------|-------------|
| `NODE_FUNCTION_ALLOW_EXTERNAL` across all `*.yml/*.yaml/*.json/*.sh/*.env*` | **0 hits** | n8n Code-node sandbox cannot `require('ioredis')` — the env that would allow it is unset. Adding it is a security/scope expansion the milestone doesn't justify (no other Code node needs it). |
| `require('ioredis')` / `require('redis')` in `workflows/*.json` | **0 hits** | No precedent for a direct client. The repo Code nodes only `require('crypto')` (a Node built-in, always allowed — e.g. `W1_IN_WA.json:717`). |
| `n8n-nodes-base.redis` in `workflows/*.json` | **21 workflows** | This IS the established Redis access pattern. |
| Redis credential id `43SDqJYMGa6RvFqW` | `W_QUEUE_METRICS.json` (the live-exported id) | The repo's checked-in workflows mostly use the placeholder `"REDIS_CREDENTIAL_ID"` (e.g. `W0_CONFIG_READER.json:37,189`, `W0_REDIS_HELPER.json:34`) or `"={{ $env.REDIS_CREDENTIAL_ID }}"` (`W15_OUTBOX_WORKER.json`), resolved at import. `43SDqJYMGa6RvFqW` is what the live n8n assigned. **Use the repo convention: `"id": "REDIS_CREDENTIAL_ID", "name": "Redis"`** so the import wires it to the same credential. |

**Why Redis nodes are correct beyond "it's the pattern":** in queue mode, executions run on *workers*; a Code-node-owned `ioredis` client would create/destroy a connection per execution (socket churn) or leak a module-level client across the worker's executions with no n8n-managed lifecycle. The `n8n-nodes-base.redis` node uses n8n's **managed, credential-backed connection** — the same one the BullMQ queue and the 21 other workflows share — which is the right lifecycle in queue mode. This directly answers the "Redis client lifecycle in queue mode" risk: **we don't manage a client; n8n does.**

---

## 2. The decided node topology (mirror of `W0_CONFIG_READER`)

`W0_CONFIG_READER.json` is the canonical cache-aside template already in the repo (`Trigger → Redis GET → Cache-Hit? Code → IF → [Return Cached] | [Strapi fetch ×2 → Merge → Redis SET ttl=60 → Return Fresh]`). Phase 20's guard is the same skeleton with the entitlement key + fail-closed evaluation. **Recommended nodes (replacing today's single "Module Guard" Code node):**

```
Start (executeWorkflowTrigger)
  → A. Guard Input Validate (Code)         # tenant_id+module_key required → fail-closed reasons (keep today's checks)
  → B. Redis GET (n8n-nodes-base.redis, op=get, key="=ralphe:entitlement:{{$json.tenant_id}}:{{$json.module_key}}", continueOnFail:true)
  → C. Guard Decide-from-cache (Code)       # parse B; if usable cached row → re-eval expiry NOW → allow/deny; set _cacheUsable
  → D. IF "_cacheUsable" (n8n-nodes-base.if)
        TRUE  → E. Return Cached Decision (Code)        # ★ ZERO Strapi nodes downstream — proves criterion 1
        FALSE → F. Strapi GET product-modules (httpRequest, continueOnFail:true, timeout)
              → G. Strapi GET tenant-entitlements (httpRequest, continueOnFail:true, timeout)
              → H. Guard Evaluate (live) (Code)         # fail-closed on Strapi error; build decision + raw row
              → I. IF "_cacheable" (n8n-nodes-base.if)  # cacheable iff NOT GUARD_ERROR_FAILCLOSED (transient never cached)
                    TRUE  → J. Redis SET (op=set, key=same, value=JSON.stringify(rawRow+fetchedAt), expire:true, ttl=<pos|neg>, continueOnFail:true) → K. Return Fresh Decision (Code)
                    FALSE → K. Return Fresh Decision (Code)   # error path skips SET (never caches a transient error)
```

**Connections note (mirror `W0_CONFIG_READER.json:210-306`):** the IF node's `main[0]` = TRUE branch, `main[1]` = FALSE branch. Use `n8n-nodes-base.if` `typeVersion:2` with `conditions.boolean[].operation: "isTrue"` (as `W0_CONFIG_READER` does). The Redis nodes are `typeVersion:1` (matches every Redis node in the repo). Code nodes `typeVersion:2`.

**Why a SEPARATE "Strapi via httpRequest node" not the in-Code `fetch()`:** the existing guard does `await fetch(...)` *inside* the Code node. That works (n8n exposes `fetch`), but for the cache-aside restructure the two Strapi calls must live on the **MISS branch only** so that on a HIT they are provably not reached. Putting them in `n8n-nodes-base.httpRequest` nodes on the FALSE branch (as `W0_CONFIG_READER` does with `cfg-strapi-fetch-05`/`cfg-platform-fetch-06`) makes "0 round-trips on hit" a *structural* property (the nodes aren't on the hit path) that a jq assertion + the pure-seam test can both verify. **Decision: convert the two `fetch()` calls to `httpRequest` nodes on the MISS branch.** (Alternative: keep `fetch()` inside an `H. Evaluate` Code node on the MISS branch — also valid and closer to today's code; either satisfies criterion 1 because the Code node is only reached on miss. Recommend httpRequest nodes for structural clarity + to match `W0_CONFIG_READER`; note the alternative in the plan.)

**Redis node param shapes (verified from repo):**
- GET: `{ "operation": "get", "key": "=ralphe:entitlement:{{$json.tenant_id}}:{{$json.module_key}}" }` — result lands as `$json` (bare value string, or `{error:{message}}` when `continueOnFail` swallows a Redis failure, per `W1_IN_WA.json:292` dedupe-parse precedent and `W0_CONFIG_READER.json:46`).
- SET with TTL: `{ "operation": "set", "key": "=...", "value": "={{ JSON.stringify($json._cacheRow) }}", "expire": true, "ttl": <seconds> }` (exactly `W0_CONFIG_READER.json:172-178` / `W0_REDIS_HELPER.json:19-26`). For the negative cache, a second SET node (shorter ttl) on the NO_ENTITLEMENT sub-branch, OR a single SET whose `ttl` is computed by the Evaluate Code node (`={{ $json._cacheTtl }}`) — recommend the **computed-ttl single SET** (fewer nodes, the Code node owns positive-vs-negative TTL choice).

---

## 3. Cache contents, key, and TTLs (criterion 1 + 2)

**Key (LOCKED — do NOT redesign):** `ralphe:entitlement:{tenant_id}:{module_key}` — byte-identical to `audit-hook.ts:122` (Phase-19 DEL) and ADR 0003 Decision 2. `{tenant_id}` = canonical UUID string (`00000000-0000-0000-0000-000000000001` in CI; live UUID on 🔴 VPS). `{module_key}` = the product-module `key` (e.g. `channel_whatsapp`, `delivery_dispatch`, `order_bot_core` — from `config/product_modules.json`).

**What to cache — the RAW row + metadata, NOT the boolean decision (criterion 2: "cached raw row's expiry re-evaluated on read"):**

```json
{ "ent": { "enabled": true, "expires_at": "2026-09-01T00:00:00Z", "config_overrides": {...} },
  "mod": { "tier": "addon", "enabled_globally": false },
  "fetchedAt": "2026-06-20T12:00:00Z" }
```

On a HIT, the `C. Guard Decide-from-cache` Code node **re-evaluates `ent.expires_at` against `new Date()` NOW** — so a row cached while still-valid but whose `expires_at` has since passed yields `EXPIRED`, never a stale allow. This is why the decision (allow/deny) is **derived on read**, not stored. (If we cached the boolean, a cached `allow` could outlive `expires_at` within the TTL window — the criterion-2 trap.)

**TTLs (Phase 20 newly decides — recommend):**

| Cache entry | TTL | Rationale |
|-------------|-----|-----------|
| Positive (entitled / global-enabled) | **300s (~5 min)** | Matches ADR 0003 Decision 3's "≤5-min positive TTL bounds staleness" pledge + the existing `MENU_CACHE_TTL_SEC=300` convention (`docker-compose.hostinger.prod.yml:398`). Phase-19's DEL evicts on any entitlement change, so 5 min is the *worst-case* staleness only for product-module changes (audit-only invalidation, ADR 0003 Decision 3). Make it env-tunable: `ENTITLEMENT_CACHE_TTL_SEC` (default 300). |
| Negative (`NO_ENTITLEMENT` / `MODULE_NOT_FOUND`) | **30–60s (shorter)** | A just-granted entitlement should become usable quickly; a long negative TTL would lock out a freshly-provisioned tenant for 5 min. Phase-19's DEL also fires on the create that grants it, but the negative entry was written under the *same key*, so the DEL evicts it — short TTL is belt-and-suspenders. Env-tunable: `ENTITLEMENT_NEG_CACHE_TTL_SEC` (default 60). |
| Transient `GUARD_ERROR_FAILCLOSED` | **NEVER cached** | Criterion 2. The `I. IF _cacheable` node routes the error path to `K. Return` **skipping the SET**. Caching a transient Strapi/Redis hiccup as a deny would convert a blip into a TTL-long outage. |

**`allkeys-lru` eviction (criterion 2):** because we cache-aside (GET → on nil, live query → SET), an LRU eviction simply produces a `GET` miss → the FALSE branch runs the live Strapi query → a fresh decision. **A miss is never a deny** — the deny only comes from a live Strapi `NO_ENTITLEMENT` row or a live Strapi *error* (fail-closed). The pure-seam test asserts `cachedValue=null → calls Strapi` (never short-circuits to deny). This is automatically true given the topology; document it + test it.

---

## 4. Fail-closed / fall-through decision matrix (criterion 2 — the load-bearing logic)

This is the heart of GRD-01. The `C. Decide-from-cache` and `H. Evaluate-live` Code nodes implement:

| Situation | Detected by | Action | Cached? | Reason emitted |
|-----------|-------------|--------|---------|----------------|
| Cache HIT, row still valid | `GET` returns a parseable JSON row, `expires_at` re-eval = future/absent | **ALLOW** — return cached decision, ZERO Strapi calls | (already cached) | `ENTITLED_CACHED` / `GLOBAL_ENABLED_CACHED` |
| Cache HIT, row now expired | parseable row, `expires_at` re-eval = past | **DENY** | (already cached; let TTL/DEL clear) | `EXPIRED` |
| Cache HIT but NEGATIVE entry | row = `{neg:true}` sentinel | **DENY** | (already cached, short TTL) | `NO_ENTITLEMENT` |
| **Cache MISS** (nil) or **LRU eviction** | `GET` returns null/'nil'/'' | fall through to **live Strapi** | will SET result | — |
| **Redis ERROR** (GET node `continueOnFail` → `{error}`) | `$json.error` present after GET | **fall through to live Strapi** (NOT a deny) | best-effort SET (may also error → swallow) | — |
| Live: module not found | Strapi product-modules `data[0]` empty | **DENY** | negative (short TTL) | `MODULE_NOT_FOUND` |
| Live: shared_core / enabled_globally | `mod.tier==='shared_core' || mod.enabled_globally` | **ALLOW** | positive | `GLOBAL_ENABLED` |
| Live: no entitlement row | tenant-entitlements `data[0]` empty | **DENY** | negative (short TTL) | `NO_ENTITLEMENT` |
| Live: entitlement expired | `ent.expires_at < now` | **DENY** | positive-row cached, expiry re-eval on next read | `EXPIRED` |
| Live: entitled | row present, not expired | **ALLOW** | positive | `ENTITLED` |
| **Strapi ERROR** (httpRequest `continueOnFail` → error, or 4xx/5xx, or token 401) | `$json.error` / non-2xx / empty body on the live fetch | **DENY (fail-closed)** | **NEVER** | `GUARD_ERROR_FAILCLOSED: <detail>` |

**Two distinct error postures (the subtle, criterion-2-critical part):**
- **Redis error → fall THROUGH (fail-OPEN toward Strapi), then Strapi is authoritative.** Redis is a cache; its failure must not deny — it degrades to today's (uncached) behavior. The `continueOnFail:true` on the GET node + an `if ($json.error) treat as miss` in the Decide Code node implements this.
- **Strapi error → DENY (fail-CLOSED).** Strapi is the source of truth; if it can't be reached/authenticated, we cannot prove entitlement → deny. This preserves today's `catch → GUARD_ERROR_FAILCLOSED` posture. The `continueOnFail:true` on the httpRequest nodes routes an error into the Evaluate Code node which inspects `$json.error`/status and returns the fail-closed reason **without SET**.

**Distinct reason prefixes already exist and are the alert-split contract (→ §6):** `GUARD_ERROR_FAILCLOSED:` (cannot-determine, **pageable**) vs `NO_ENTITLEMENT:`/`MODULE_NOT_FOUND:`/`EXPIRED:` (legitimate denials, **not paged**). Keep these prefixes stable; 20-03 keys alerting off them.

---

## 5. ENT-03 — token wiring + preflight (the gap + the fix)

### The exact gap (grep-verified)
- `W0_MODULE_GUARD.json:30-31` reads `$env.STRAPI_API_URL` and `$env.STRAPI_API_TOKEN_INTERNAL`.
- **Neither is in the n8n-main env block** (`docker-compose.hostinger.prod.yml:360-448`) **nor the n8n-worker env block** (`:517+`), and **neither is in `docker-compose.base.yml`** n8n services (only `STRAPI_SUPER_ADMIN_*` under the *Strapi* service). So at runtime both are `undefined` → guard `fetch()` hits `undefined/api/...` with `Bearer undefined` → 401/network error → `catch` → `GUARD_ERROR_FAILCLOSED` → **total inbound + operator lockout, silently.** This is the precise ENT-03 hazard.
- **`config/.env.example`** has `STRAPI_API_TOKEN_SALT` (line 570) but **NOT** `STRAPI_API_TOKEN_INTERNAL` and **NOT** `STRAPI_API_URL`.
- **Secrets inventory** = `docs/SECRETS_ROTATION_REQUIRED.md` — it **already lists** `STRAPI_API_TOKEN_INTERNAL` (line 23, P1). So the inventory is satisfied; the gap is compose + env-example + preflight + (optionally) a clearer note that this is the *guard's* token.

### The fix (20-02)
1. **Compose (both files, both n8n services):** add to the `environment:` array of `n8n-main` AND `n8n-worker` in `docker-compose.hostinger.prod.yml` and `docker-compose.base.yml`:
   ```yaml
   - STRAPI_API_URL=${STRAPI_API_URL:-http://strapi:1337}
   - STRAPI_API_TOKEN_INTERNAL=${STRAPI_API_TOKEN_INTERNAL:?STRAPI_API_TOKEN_INTERNAL must be set — W0_MODULE_GUARD fails closed without it (total inbound/operator lockout)}
   ```
   The `${VAR:?message}` form is the **established repo fail-fast precedent** (`docker-compose.hostinger.prod.yml:94-101` does it for `STRAPI_ADMIN_JWT_SECRET`, `STRAPI_JWT_SECRET`, `STRAPI_API_TOKEN_SALT`, `STRAPI_ENCRYPTION_KEY`, `STRAPI_APP_KEYS`). This makes `docker compose up` itself **fail fast with a clear message** before n8n even boots — the strongest, lowest-code form of the criterion-3 check. **Caveat (criterion 3 sub-clause "the fail-closed flip is not made before the secret exists"):** because today the token is absent and the guard already fails closed, the `${VAR:?}` hard-fail must land in the SAME plan/commit that ensures the token is provisioned, OR use `${VAR:-}` (soft) on `base`/dev and `${VAR:?}` (hard) only on `hostinger.prod` — recommend **hard on prod, soft-with-preflight-warn on base/dev** so local/CI compose-config doesn't break while prod refuses to start tokenless. (Open question O-2.)
2. **`config/.env.example`:** add `STRAPI_API_URL=http://strapi:1337` and `STRAPI_API_TOKEN_INTERNAL=tobemodified   # [SECRET] internal Strapi API token used by W0_MODULE_GUARD; provision real value on VPS`. The `tobemodified` placeholder + `# [SECRET]` matches the file's existing convention (`STRAPI_API_TOKEN_SALT=tobemodified  # [SECRET]`, line 570) and is **gitleaks-allowlisted** (`.gitleaks.toml:54-55` allowlists `config/.env.example`; `:87` allowlists `example`). Adding it also makes `env_sync_check.sh` (which diffs `.env.example` vs prod `.env`) flag a prod `.env` that's missing the token.
3. **Startup preflight (the criterion-3 "fails fast with a clear message" check):** extend the existing **`scripts/preflight.sh`** — add `STRAPI_API_TOKEN_INTERNAL` (and `STRAPI_API_URL`) to its `REQ_VARS` array (`scripts/preflight.sh:6-10`); the script already loops `REQ_VARS`, prints `❌ Missing env: <VAR>`, sets `missing=1`, and `exit 1`s — so adding the var name is a one-line change that yields the exact fail-fast-with-message behavior. **Plus a CI assertion** (in `phase-20-assertions.yml`) that (a) the var appears in both compose files' n8n env, (b) appears in `.env.example`, (c) appears in the secrets inventory, and (d) `preflight.sh` lists it — and a **negative test** that runs `preflight.sh` with the var unset and asserts non-zero exit + a message mentioning the token. (`scripts/preflight-prod.sh` exists too — check whether it should mirror; recommend adding to `preflight.sh` which is the general one, and noting `preflight-prod.sh` if it has its own REQ list.)

**Recommendation on where the fail-fast lives:** **both** — the compose `${VAR:?}` (fails `docker compose up` instantly, no script needed, can't be skipped) **and** `scripts/preflight.sh` (the documented pre-deploy gate, CI-testable without docker). The compose form is the real runtime guarantee; the preflight form is the CI-verifiable, docker-free proof for the success criterion.

---

## 6. Alert split — `GUARD_ERROR_FAILCLOSED` vs `NO_ENTITLEMENT` (criterion 4 — 20-03)

### Current state
The guard returns `{allowed, reason}`; callers branch on `allowed` (`W1_IN_WA.json:198` `B0 - Guard OK?` IF) and the FALSE branch goes to **`B0 - Log Deny (DB)`** (an INSERT into `security_events`, `W1_IN_WA.json:240`) then **`END - Drop/Done`**. So denials are *logged to `security_events`* but **all reasons are treated identically** — a `GUARD_ERROR_FAILCLOSED` (token missing → total outage) looks exactly like a routine `NO_ENTITLEMENT` (tenant simply doesn't have the module). The alerting plane is **`W8_OPS.json`** (`errorTrigger E1 → E2 Normalize → E3 Save Error (DB) → E4 Optional Alert Webhook` via `ALERT_WEBHOOK_URL`, `W8_OPS.json:120-124`) and the `security_events` table (severity column already exists — `W1_IN_WA.json:240` inserts `'HIGH'`).

### The split (recommend)
Make the distinction structural via the **reason prefix** (already distinct — §4) and a **severity classifier**:

| Reason prefix | Class | Severity | Pageable? | Routing |
|---------------|-------|----------|-----------|---------|
| `GUARD_ERROR_FAILCLOSED*` | cannot-determine (infra/token/Strapi down) | **HIGH / page** | **YES** | `security_events` severity `HIGH` + emit to `ALERT_WEBHOOK_URL` (the W8_OPS alert path) with `alert_key='GUARD_FAILCLOSED'` so a missing/expired token pages on-call |
| `NO_ENTITLEMENT*`, `MODULE_NOT_FOUND*`, `EXPIRED*` | legitimate denial (tenant lacks/lost module) | **INFO / LOW** | NO | `security_events` severity `LOW` (or a counter), **no page** — these are normal business outcomes |
| `GUARD_ERROR: tenant_id not provided` / `module_key not provided` (input errors) | caller bug | **MEDIUM** | maybe | log/count; not a token outage |

**Implementation seam:** a tiny **pure reason-classifier** `scripts/guard/classify-deny.mjs` exporting `classify(reason) -> {class, severity, pageable, alertKey}` — unit-tested with `node --test` (every prefix → expected severity; an unknown reason → safe default `HIGH` so a new failure mode isn't silently swallowed). The guard's `Return …` nodes attach `_alert: {severity, pageable, alertKey}` to the output; the caller's deny branch (e.g. `W1_IN_WA`'s `B0 - Log Deny`) writes `severity` from `_alert.severity` instead of a hardcoded value, and an IF on `_alert.pageable` fans the FAILCLOSED case to the alert webhook. **To keep file ownership disjoint from 20-01**, 20-03 owns: the classifier seam + its test + the `security_events`/alert-webhook wiring + a structural assertion that the guard emits distinct reason prefixes — but the *guard topology* (nodes/connections) is 20-01's. The cleanest boundary: 20-01's `Return` Code nodes already set the `reason` (they do today); 20-03 adds the `_alert` classification either *inside those same Return nodes* (then 20-03 must coordinate with 20-01 — sequence them) **or** in the **callers'** deny branches (fully disjoint from the guard file). **Recommend:** the classifier function lives in `scripts/guard/classify-deny.mjs` (20-03), and the guard's Return nodes (20-01) import/inline a copy of the prefix→severity map; document the shared contract in the plan so both reference the same prefixes. Simplest disjoint option: **20-03 keys the alert split entirely off the existing `reason` string in the caller/W8_OPS path** (no guard-node edits) — the guard already emits distinct prefixes, so the classifier can live purely downstream. (Open question O-3.)

---

## 7. Validation Architecture

> `workflow.nyquist_validation: true` in `.planning/config.json` — this section is REQUIRED.

### The testable seam (proving "hit skips both Strapi fetches" without booting n8n)
Booting n8n in queue mode in CI is heavy and unnecessary. **Extract the guard's cache-aside DECISION logic into a pure, Strapi-free, n8n-free function** — exactly Phase 19's `audit-hook.ts` discipline (a pure seam + a thin adapter). The seam:

```
scripts/guard/entitlement-decision.mjs  exports (TYPE-STRIPPABLE style if .ts — see Blocker note):
  buildCacheKey(tenant_id, module_key) -> "ralphe:entitlement:..."   (must equal audit-hook.ts:122 byte-for-byte)
  decideFromCache(cachedRaw, now) -> { hit:boolean, allowed?, reason?, cacheUsable }   (re-evaluates expiry on read)
  evaluateLive(moduleRes, entRes, now) -> { allowed, reason, cacheRow?, cacheable, ttl }  (fail-closed on error; transient never cacheable)
  classifyDeny(reason) -> { severity, pageable, alertKey }            (shared with 20-03)
```

The guard's Code nodes (20-01) call these; the n8n nodes only do the Redis GET/SET + Strapi httpRequest IO around them. **The test injects mock `fetchFns` and asserts call counts:**

```js
// node --test, no n8n, no Strapi, no Redis needed for the decision-logic tests
import test from 'node:test'; import assert from 'node:assert';
import { decideFromCache, evaluateLive, buildCacheKey } from '../entitlement-decision.mjs';

test('cache HIT → 0 Strapi fetches', () => {
  let strapiCalls = 0; const fetchMod = () => { strapiCalls++; };
  const cached = JSON.stringify({ ent:{enabled:true,expires_at:null}, mod:{tier:'addon'}, fetchedAt:'...' });
  const d = decideFromCache(cached, Date.now());
  assert.equal(d.cacheUsable, true); assert.equal(d.allowed, true);
  assert.equal(strapiCalls, 0);                       // ★ criterion 1
});
test('Redis error → falls through to Strapi (not a deny)', () => {
  const d = decideFromCache(null, Date.now());        // null == miss/eviction/error-treated-as-miss
  assert.equal(d.cacheUsable, false);                 // → MISS branch runs live query
});
test('Strapi error → DENY fail-closed', () => {
  const d = evaluateLive({error:'ECONNREFUSED'}, null, Date.now());
  assert.match(d.reason, /^GUARD_ERROR_FAILCLOSED/); assert.equal(d.allowed, false);
  assert.equal(d.cacheable, false);                   // ★ transient never cached
});
test('expired cached row re-evaluated on read → DENY', () => {
  const cached = JSON.stringify({ ent:{enabled:true,expires_at:'2000-01-01T00:00:00Z'}, mod:{tier:'addon'} });
  const d = decideFromCache(cached, Date.now());
  assert.equal(d.allowed, false); assert.match(d.reason, /^EXPIRED/);
});
test('LRU eviction (miss) → live query, never spurious deny', () => {
  assert.equal(decideFromCache(null, Date.now()).cacheUsable, false);  // miss, not deny
});
test('buildCacheKey matches Phase-19 DEL byte-for-byte', () => {
  assert.equal(buildCacheKey('00000000-0000-0000-0000-000000000001','channel_whatsapp'),
               'ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp');
});
```

### Test Framework
| Property | Value |
|----------|-------|
| Framework | **`node --test`** (Node **22.22.2** at `/opt/node22/bin/node` — verified) for the pure decision seam + the classifier; **`jq`** (`/usr/bin/jq` — verified) for structural workflow assertions; **`bash` + `redis-cli`** (`/usr/bin/redis-cli`, redis-server 7.0.15 — verified) for an optional live SET→GET round-trip; **`bash`** for the preflight negative test |
| Config file | `.github/workflows/phase-20-assertions.yml` (new, Wave 0) — mirror `.github/workflows/phase-19-assertions.yml`; **pin `actions/setup-node` to `node-version: '22'`** (Phase 19's BLOCKER A — Node 20 lacks `--experimental-strip-types`; bite avoided by writing the seam as `.mjs` plain JS, but pin 22 anyway for parity/safety) |
| Quick run | `node --test scripts/guard/__tests__/entitlement-decision.test.mjs scripts/guard/__tests__/classify-deny.test.mjs` |
| Full suite | `bash scripts/test-phase20.sh` (runs node-tests + jq structural checks on `W0_MODULE_GUARD.json` + the preflight negative test + an optional ephemeral-redis round-trip) — all **docker-free, locally runnable** |

> **Blocker note (carry from Phase 19):** if any seam is authored as `.ts` and the test imports it via `--experimental-strip-types`, the CI `setup-node` MUST be `node-version: '22'`. **Recommendation: author the guard seam as `.mjs` plain JS** (it has no Strapi/knex types to strip — unlike Phase 19's `audit-hook.ts` which needed zod/knex types), sidestepping the strip-types pin entirely. Still pin Node 22 in CI for consistency.

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GRD-01 | cache HIT → **0** Strapi round-trips | node --test (mock fetch, assert call count 0) | `node --test scripts/guard/__tests__/entitlement-decision.test.mjs` | ❌ Wave 0 |
| GRD-01 | Redis error → falls through to Strapi (not deny) | node --test | same | ❌ Wave 0 |
| GRD-01 | Strapi error → DENY (fail-closed) + NOT cached | node --test | same | ❌ Wave 0 |
| GRD-01 | expired cached row re-evaluated on read → DENY | node --test | same | ❌ Wave 0 |
| GRD-01 | LRU eviction (miss) → live query, never spurious deny | node --test | same | ❌ Wave 0 |
| GRD-01 | cache key == Phase-19 DEL key byte-for-byte | node --test + jq grep | `jq` finds `ralphe:entitlement:` in GET+SET node keys of `W0_MODULE_GUARD.json` | ❌ Wave 0 |
| GRD-01 | guard has Redis GET + Redis SET nodes (n8n-nodes-base.redis) keyed to the pattern, TTLs present | jq structural | `jq '[.nodes[]|select(.type=="n8n-nodes-base.redis")]\|length>=2'` + key/ttl assertions on `W0_MODULE_GUARD.json` | ❌ Wave 0 |
| GRD-01 | both Strapi fetches still present for the MISS path | jq/grep | assert 2 httpRequest nodes (or 2 `fetch(` in the miss Code node) hitting `product-modules` + `tenant-entitlements` | ❌ Wave 0 |
| GRD-01 | fail-closed reasons present | grep | `grep GUARD_ERROR_FAILCLOSED W0_MODULE_GUARD.json` | ❌ Wave 0 |
| GRD-01 | (optional) live SET→GET round-trip on the canonical key | bash + redis-cli | ephemeral `redis-server --port 7390`; SET ttl; GET returns row; assert | ❌ Wave 0 |
| ENT-03 | token declared in BOTH compose files' n8n env | grep | `grep STRAPI_API_TOKEN_INTERNAL docker-compose.hostinger.prod.yml docker-compose.base.yml` | ❌ Wave 0 |
| ENT-03 | token in `config/.env.example` | grep | `grep STRAPI_API_TOKEN_INTERNAL config/.env.example` | ❌ Wave 0 |
| ENT-03 | token in secrets inventory | grep | `grep STRAPI_API_TOKEN_INTERNAL docs/SECRETS_ROTATION_REQUIRED.md` (already TRUE — line 23) | ✅ exists |
| ENT-03 | preflight fails fast (non-zero + clear msg) when unset | bash negative test | `env -u STRAPI_API_TOKEN_INTERNAL bash scripts/preflight.sh; assert $? != 0 && output mentions token` | ❌ Wave 0 |
| GRD-01/4 | `GUARD_ERROR_FAILCLOSED` classified pageable; `NO_ENTITLEMENT` not | node --test | `node --test scripts/guard/__tests__/classify-deny.test.mjs` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `node --test` on the changed seam (quick, no docker); `jq` structural check on `W0_MODULE_GUARD.json`; `bash -n scripts/preflight.sh`.
- **Per wave merge:** full `bash scripts/test-phase20.sh` + `phase-20-assertions.yml`.
- **Phase gate:** full suite green before `/gsd:verify-work`; 🔴 VPS import + token-provision tracked as deferred.

### Wave 0 Gaps
- [ ] `scripts/guard/entitlement-decision.mjs` — the pure decision seam (covers GRD-01 logic)
- [ ] `scripts/guard/classify-deny.mjs` — the reason→severity classifier (covers criterion 4 / 20-03)
- [ ] `scripts/guard/__tests__/entitlement-decision.test.mjs` + `classify-deny.test.mjs` — `node --test`
- [ ] `scripts/test-phase20.sh` — local harness (node-tests + jq structural + preflight negative + optional ephemeral redis), docker-free
- [ ] `.github/workflows/phase-20-assertions.yml` — mirror `phase-19-assertions.yml`; structural jq job + node-test job (`setup-node` pinned `'22'`) + (optional) `redis:7-alpine` service for a live round-trip
- [ ] (no framework install — `node --test`, `jq`, `redis-cli`/`redis-server`, `bash` all present at `/opt/node22/bin` & `/usr/bin`)

---

## Standard Stack

### Core (all already in repo — milestone constraint: NO new runtime libraries, NO new n8n nodes)
| Component | Version | Purpose | Source |
|-----------|---------|---------|--------|
| `n8n-nodes-base.redis` (op `get`/`set`, `expire`+`ttl`) | bundled (n8n 2.9.4) | The guard's ONLY supported Redis access; GET on hot path + SET with TTL on miss | `W0_CONFIG_READER.json:22-42,172-194`; 21 workflows |
| `n8n-nodes-base.httpRequest` (typeVersion 4) | bundled | The two Strapi fetches on the MISS branch (product-modules + tenant-entitlements) | `W0_CONFIG_READER.json:92-156` |
| `n8n-nodes-base.code` (typeVersion 2) | bundled | Decide-from-cache / evaluate-live / return; calls the pure seam logic | existing guard + `W0_CONFIG_READER` |
| `n8n-nodes-base.if` (typeVersion 2) | bundled | hit/miss + cacheable branching | `W0_CONFIG_READER.json:57-76` |
| Redis credential (`"id":"REDIS_CREDENTIAL_ID","name":"Redis"`; live id `43SDqJYMGa6RvFqW`) | n8n-managed | the shared Redis connection (queue-mode safe; n8n owns lifecycle) | `W0_CONFIG_READER.json:35-39`; `W_QUEUE_METRICS.json` |
| `node --test` | Node 22.22.2 | pure decision-seam + classifier unit tests (no n8n/Strapi boot) | host-verified `/opt/node22/bin/node` |
| `jq` | system | structural assertions on `W0_MODULE_GUARD.json` | host-verified `/usr/bin/jq` |
| `redis-server`/`redis-cli` | 7.0.15 | optional local + CI live round-trip | host-verified `/usr/bin/redis*` |
| compose `${VAR:?message}` | docker compose | fail-fast on missing `STRAPI_API_TOKEN_INTERNAL` at `up` | `docker-compose.hostinger.prod.yml:94-101` |
| `scripts/preflight.sh` `REQ_VARS` loop | bash | the documented pre-deploy fail-fast gate (CI-testable, docker-free) | `scripts/preflight.sh:6-24,61-64` |

**Installation:** None. No new packages, no new n8n nodes, no new credentials. **Do NOT** introduce `NODE_FUNCTION_ALLOW_EXTERNAL` / a Code-node `ioredis` client (not the repo pattern; unnecessary scope expansion).

**Version verification (2026-06-20):** n8n image pin is in compose (`N8N_VERSION`); Redis 7.0.15 (local) / `redis:7-alpine` (CI); Node 22.22.2. No npm registry fetch needed — Phase 20 adds no runtime dependency.

---

## Architecture Patterns

### Recommended file layout (disjoint ownership for 3 plans)
```
workflows/W0_MODULE_GUARD.json                          # 20-01 ONLY — the cache-aside restructure
scripts/guard/entitlement-decision.mjs                  # 20-01 — pure decision seam (the testable keystone)
scripts/guard/__tests__/entitlement-decision.test.mjs   # 20-01 — node --test
docker-compose.hostinger.prod.yml                       # 20-02 — add token+url to n8n-main & n8n-worker env (${VAR:?})
docker-compose.base.yml                                 # 20-02 — same
config/.env.example                                     # 20-02 — add STRAPI_API_TOKEN_INTERNAL + STRAPI_API_URL
docs/SECRETS_ROTATION_REQUIRED.md                       # 20-02 — confirm/annotate (already lists it L23)
scripts/preflight.sh                                    # 20-02 — add token to REQ_VARS
scripts/guard/classify-deny.mjs                         # 20-03 — reason→severity classifier
scripts/guard/__tests__/classify-deny.test.mjs          # 20-03 — node --test
(alert wiring: W8_OPS / caller deny-branch severity)    # 20-03 — keyed off reason prefix (see O-3 for boundary)
scripts/test-phase20.sh                                 # 20-01 or 20-03 (shared harness — assign to 20-01, extend in 20-03)
.github/workflows/phase-20-assertions.yml               # 20-01 (structural+node-test), 20-02 appends ENT-03 grep job, 20-03 appends classifier job
```

### Pattern 1: Redis nodes around a pure-logic Code node (the queue-mode-safe cache-aside)
**What:** GET/SET via `n8n-nodes-base.redis` (n8n-managed connection); all branching/decision logic in Code nodes that call a pure `.mjs` seam; the two Strapi calls live on the MISS branch only.
**When:** Always in this repo — Code-node `require('ioredis')` is unavailable (`NODE_FUNCTION_ALLOW_EXTERNAL` unset) and managed connections are correct for queue mode.
**Source:** `W0_CONFIG_READER.json` (the exact template).

### Pattern 2: Pure decision seam + thin n8n adapter (testability keystone)
**What:** `entitlement-decision.mjs` has zero n8n/Strapi imports — takes `(cachedRaw, now)` / `(moduleRes, entRes, now)` and returns the decision + call-count-observable behavior. Mirrors Phase-19 `audit-hook.ts`.
**When:** Always — makes "0 fetches on hit" a unit-test assertion with no n8n boot.

### Pattern 3: Compose `${VAR:?msg}` + preflight `REQ_VARS` double fail-fast
**What:** compose refuses `up` on a missing required secret (runtime guarantee); `preflight.sh` refuses pre-deploy (CI-testable). Both for `STRAPI_API_TOKEN_INTERNAL`.
**Source:** `docker-compose.hostinger.prod.yml:94-101` + `scripts/preflight.sh:6-24`.

### Anti-Patterns to Avoid
- **Code-node `require('ioredis')`** — sandbox-blocked here; would force `NODE_FUNCTION_ALLOW_EXTERNAL` (scope creep, unprecedented).
- **Caching the boolean decision** — breaks criterion-2's "expiry re-evaluated on read"; cache the raw row + re-derive.
- **Caching a transient `GUARD_ERROR_FAILCLOSED`** — converts a blip into a TTL-long outage; the error path must skip SET.
- **A new cache-key shape** — must be byte-identical to `audit-hook.ts:122` or Phase-19 DEL won't evict.
- **`SCAN`/`KEYS` in the guard** — single-threaded Redis hot-path killer; the guard only does exact-key GET/SET (no enumeration needed).
- **Hard `${VAR:?}` on base/dev compose before the token exists** — would break local/CI `compose config`; hard on prod, soft+preflight elsewhere.
- **Redis error → deny** — Redis is a cache; its failure must fall THROUGH to Strapi, not deny. Only *Strapi* errors deny.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Redis access from n8n | A Code-node `ioredis` client + `NODE_FUNCTION_ALLOW_EXTERNAL` | `n8n-nodes-base.redis` GET/SET nodes | The repo's only pattern; n8n owns the connection lifecycle (queue-mode safe). |
| Cache-aside skeleton | A bespoke hit/miss flow | Copy `W0_CONFIG_READER.json`'s topology | Proven in-repo template (GET→Code→IF→fetch→SET). |
| Cache key | A new key format | `ralphe:entitlement:{tenant}:{module}` from `audit-hook.ts:122` | MUST match Phase-19 DEL byte-for-byte. |
| Required-secret fail-fast | A custom env-check in the workflow | compose `${VAR:?msg}` + `preflight.sh` REQ_VARS | Both already established; compose can't be bypassed, preflight is CI-testable. |
| Secrets inventory | A new doc | `docs/SECRETS_ROTATION_REQUIRED.md` (already lists the token) | Inventory already satisfied; just annotate. |
| Deny-reason alert routing | A new alert system | The existing `security_events` severity column + `W8_OPS` `ALERT_WEBHOOK_URL` path keyed off the reason prefix | Reuses the shipped alerting plane. |
| Proving "0 fetches on hit" | Booting n8n in CI | A pure `.mjs` seam + `node --test` mock-fetch call-count assertion | No n8n boot; fast, deterministic, docker-free. |

**Key insight:** Phase 20's hard parts are *already decided by the codebase* — the Redis-access mechanism (Redis nodes, forced by the unset `NODE_FUNCTION_ALLOW_EXTERNAL`), the cache-aside topology (`W0_CONFIG_READER`), the key (`audit-hook.ts`/ADR 0003), and the fail-fast idioms (`${VAR:?}` + `preflight.sh`). The genuinely new work is the **fail-closed/fall-through decision matrix** (§4) and the **TTL + raw-row-not-decision caching** discipline (§3), both isolated into a testable pure seam.

---

## Common Pitfalls

### Pitfall 1: Trying to `require('ioredis')` in the guard Code node
**What goes wrong:** Throws (module not allow-listed) — `NODE_FUNCTION_ALLOW_EXTERNAL` is unset repo-wide.
**Avoid:** Use `n8n-nodes-base.redis` GET/SET nodes around the Code node (§1/§2).

### Pitfall 2: Caching the decision instead of the raw row
**What goes wrong:** A cached `allow` survives `expires_at` within the TTL window → an expired entitlement still passes.
**Avoid:** Cache `{ent, mod, fetchedAt}`; re-derive allow/deny + re-check `expires_at` on every read (criterion 2 / §3).

### Pitfall 3: Caching a transient guard error
**What goes wrong:** A one-off Strapi 500 cached as `GUARD_ERROR_FAILCLOSED`/deny → TTL-long outage from a momentary blip.
**Avoid:** The error path skips SET (`IF _cacheable` FALSE → Return, no SET). Only definitive ALLOW/NO_ENTITLEMENT/MODULE_NOT_FOUND are cached (criterion 2 / §4).

### Pitfall 4: Redis error treated as a deny
**What goes wrong:** Redis down → guard denies everything → total outage, even though Strapi is fine.
**Avoid:** Redis error (GET node `continueOnFail` → `{error}`) is a **miss** → fall through to live Strapi. Only *Strapi* errors deny (§4).

### Pitfall 5: Cache key drift from Phase-19 DEL
**What goes wrong:** Guard GET/SET uses a key shape ≠ `audit-hook.ts:122` → a revoked entitlement's DEL never evicts the live cache → stale grant survives (the AUD-02/GRD-01 regression).
**Avoid:** `buildCacheKey()` unit-tested to equal `ralphe:entitlement:{tenant}:{module}` byte-for-byte; jq grep asserts the GET+SET node keys.

### Pitfall 6: Flipping fail-closed-hard before the token exists
**What goes wrong:** Hard `${VAR:?}` lands while the token is unprovisioned → `docker compose up` fails on every env (incl. CI/dev) OR (if the guard already fail-closes) a total lockout persists.
**Avoid:** Provision/declare the token in the SAME change; hard `${VAR:?}` on **prod only**, soft `${VAR:-}` + preflight-warn on base/dev (criterion 3 sub-clause / O-2).

### Pitfall 7: `allkeys-lru` eviction mistaken for a deny
**What goes wrong:** Under memory pressure Redis evicts the entitlement key; if the guard treated "key gone" as "denied", a healthy tenant gets locked out.
**Avoid:** Cache-aside means eviction = miss = live query. Test asserts `decideFromCache(null) → cacheUsable:false` (→ live query), never deny (§3/§7).

### Pitfall 8: Strapi-error detection with `httpRequest` + `continueOnFail`
**What goes wrong:** With `continueOnFail:true`, a 401 (missing token) or 5xx may surface as an item with `{error}` OR as an empty/odd body rather than throwing — if the Evaluate node only catches thrown errors it may mis-read a 401 as "no rows" → `NO_ENTITLEMENT` (wrong reason; not pageable).
**Avoid:** In Evaluate, treat `$json.error` present, a non-2xx status, or a structurally-invalid body as `GUARD_ERROR_FAILCLOSED` (not `NO_ENTITLEMENT`) — so a missing token pages (criterion 4). Distinguish "valid response, zero rows" (NO_ENTITLEMENT) from "couldn't get a valid response" (FAILCLOSED).

### Pitfall 9: Node 20 in CI for a type-stripped seam
**What goes wrong:** If the seam is `.ts` + `--experimental-strip-types`, CI on default Node 20 fails (bit Phase 19 — BLOCKER A).
**Avoid:** Author the seam as `.mjs` (no types to strip) AND pin `setup-node` `node-version: '22'` in `phase-20-assertions.yml`.

---

## State of the Art

| Old Approach | Current Approach (Phase 20) | When | Impact |
|--------------|-----------------------------|------|--------|
| Guard does 2 synchronous Strapi `fetch()` per inbound message, no cache (`W0_MODULE_GUARD.json` single Code node) | Cache-aside via Redis GET/SET nodes; HIT skips both fetches | Phase 20 | Latency + Strapi load drop on the hottest path (every inbound msg) |
| Phase 19 ships the DEL side (`audit-hook.ts:122`) with the key locked but no reader | Phase 20 ships the GET/SET side on the same locked key | P19→P20 | The invalidation hook had to land FIRST (else revocation couldn't evict) — why P20 depends on P19 |
| `STRAPI_API_TOKEN_INTERNAL` read by the guard but wired into NO compose env / NO `.env.example` | First-class secret: both composes' n8n env (`${VAR:?}`), `.env.example`, secrets inventory, preflight fail-fast | Phase 20 | A missing token fails fast with a clear message instead of a silent total lockout |
| All guard denials logged identically (`security_events`, one severity) | `GUARD_ERROR_FAILCLOSED` (pageable HIGH) vs `NO_ENTITLEMENT` (LOW, normal) split by reason prefix | Phase 20 | A missing/expired token pages on-call rather than masquerading as routine denials |

**Deprecated/outdated:** the all-in-one-Code-node guard (no separation of cache vs live vs decision) — replaced by the Redis-nodes + pure-seam structure.

---

## Open Questions

1. **O-1: Strapi fetch as `httpRequest` nodes vs in-Code `fetch()` on the miss branch.**
   - Known: both satisfy "0 round-trips on hit" (the fetches are only on the FALSE/miss branch). `httpRequest` nodes make it a *structural* (jq-assertable) property and match `W0_CONFIG_READER`; in-Code `fetch()` is closer to today's guard and keeps logic in the pure seam's sibling.
   - Recommendation (sensible default): **`httpRequest` nodes on the miss branch** for structural clarity + jq-verifiability; document the in-Code alternative as acceptable if the planner prefers minimal node churn. Either way the *decision* logic stays in `entitlement-decision.mjs`.

2. **O-2: Hard `${VAR:?}` vs soft `${VAR:-}` for the token across compose files.**
   - Known: hard fails `compose up`/`compose config` instantly (strongest), but breaks any env where the token isn't set (incl. CI `compose config` lint, local dev).
   - Recommendation: **hard `${VAR:?message}` on `docker-compose.hostinger.prod.yml`** (the prod runtime guarantee) + **soft `${VAR:-}` on `docker-compose.base.yml`/dev** backed by `scripts/preflight.sh` (the pre-deploy gate). Ensures prod can't start tokenless while CI/dev compose-config stays green.

3. **O-3: Alert-split boundary — guard Return nodes (20-01) vs downstream classifier (20-03).**
   - Known: the guard already emits distinct reason prefixes; the split can be done purely downstream (caller deny-branch / W8_OPS keying off `reason`) with ZERO guard-node edits (fully disjoint from 20-01), OR by attaching `_alert` inside the guard's Return nodes (richer, but couples 20-03 to the guard file 20-01 owns).
   - Recommendation: **downstream-only classification** (`scripts/guard/classify-deny.mjs` consumed in the caller deny path + W8_OPS) so 20-03 never touches `W0_MODULE_GUARD.json` — clean disjoint ownership. The guard just keeps emitting the stable prefixes (20-01's job). If the planner wants the `_alert` envelope on the guard output, sequence 20-03 after 20-01 and have 20-01's Return nodes import the same classifier.

4. **O-4: TTL exact values + env var names.**
   - Recommendation: positive `ENTITLEMENT_CACHE_TTL_SEC` default **300**; negative `ENTITLEMENT_NEG_CACHE_TTL_SEC` default **60**. Add both (soft `${VAR:-300}` / `${VAR:-60}`) to the n8n compose env + `.env.example` in 20-02 (or 20-01 if the planner keeps all guard-tunables together — recommend 20-02 since it owns env wiring). Confirm 300 satisfies "≈5-min" and ADR 0003's "≤5-min" pledge (it does).

5. **O-5: Does `scripts/preflight-prod.sh` need the token too?** `preflight.sh` is the general gate; `preflight-prod.sh` exists separately. Recommendation: add the token to `preflight.sh` `REQ_VARS` (the one the CI negative test exercises) and check whether `preflight-prod.sh` has its own REQ list to mirror — annotate in 20-02. (Low-risk; read both during planning.)

---

## 🔴 VPS Deferrals
- **Importing the restructured `W0_MODULE_GUARD.json`** into the live n8n (re-wires the `REDIS_CREDENTIAL_ID` placeholder to the live `43SDqJYMGa6RvFqW` credential on import).
- **Provisioning the real `STRAPI_API_TOKEN_INTERNAL` value** on the VPS (a Strapi-admin-generated internal API token) into the prod env — and confirming `STRAPI_API_URL` points at the in-network Strapi (`http://strapi:1337`). The hard `${VAR:?}` on prod means prod n8n won't start until this exists (the desired guarantee).
- **Confirming the prod Redis** the guard's GET/SET targets is the SAME Redis the Phase-19 `DEL` writes to (same `REDIS_CREDENTIAL_ID` / `QUEUE_BULL_REDIS_HOST=redis`) — so invalidation and caching share a keyspace.
- **`allkeys-lru` / maxmemory policy** confirmation on prod Redis (the criterion mentions LRU eviction — verify the prod Redis maxmemory-policy; cache-aside is correct regardless, but document the assumption).

---

## Sources

### Primary (HIGH confidence — direct repo reads, line-cited)
- `workflows/W0_MODULE_GUARD.json:18,30-31` — the single "Module Guard" Code node; `$env.STRAPI_API_URL`/`$env.STRAPI_API_TOKEN_INTERNAL`; `GUARD_ERROR_FAILCLOSED`/`NO_ENTITLEMENT`/`MODULE_NOT_FOUND`/`EXPIRED` reason prefixes; tenant_id required; 2× `fetch()` (product-modules + tenant-entitlements)
- `workflows/W0_CONFIG_READER.json:22-208` — the canonical cache-aside template (Redis GET `continueOnFail` → Cache-Hit? Code → IF → [Return Cached] | [httpRequest ×2 → Merge → Redis SET expire+ttl=60 → Return Fresh]); connections `:210-306`
- `workflows/W0_REDIS_HELPER.json:19-38` — Redis SET with `nx`/`expire`/`ttl` + `continueOnFail`; result-parse Code node (`redisResult.error` → fallback) `:43`
- `workflows/W15_OUTBOX_WORKER.json:56-72` — Redis GET node shape + `"id":"={{ $env.REDIS_CREDENTIAL_ID }}"` credential form; `ralphe:outbox:` key
- `workflows/W1_IN_WA.json:176-211,240-246,667,1158-1194` — guard called via `executeWorkflow` with `{module_key:'channel_whatsapp', tenant_id}`; `B0 - Guard OK?` IF on `$json.allowed`; deny → `B0 - Log Deny (DB)` (security_events, severity 'HIGH') → `END - Drop/Done`; `ralphe:replay:`/`ralphe:quarantine:` keys; `require('crypto')` (built-in) precedent `:717`
- `workflows/W8_OPS.json:78-124` — alerting plane: `errorTrigger E1 → E2 Normalize → E3 Save Error (DB) → E4 Optional Alert Webhook` (`ALERT_WEBHOOK_URL`)
- `inventory-cms/src/api/tenant-entitlement/content-types/tenant-entitlement/audit-hook.ts:20-21,111-124` — the Phase-19 DEL side; `ralphe:entitlement:${tenant_id}:${module_key}` (the byte-for-byte contract); pure-seam discipline to mirror
- `docs/adr/0003-entitlement-audit-placement.md:62-94` — Decision 2 (cache-key LOCKED) + Decision 3 (product-module audit-only invalidation; ≤5-min positive TTL bounds staleness)
- `docker-compose.hostinger.prod.yml:94-101` (`${VAR:?msg}` fail-fast precedent), `:360-448` (n8n-main env — NO STRAPI_API_TOKEN_INTERNAL/URL), `:398` (`MENU_CACHE_TTL_SEC=300`), `:439` (`ALERT_WEBHOOK_URL`); `:517+` (n8n-worker env)
- `docker-compose.base.yml:257-263` — Strapi `${VAR:?}` + NO STRAPI_API_TOKEN_INTERNAL in n8n services
- `config/.env.example:570` — `STRAPI_API_TOKEN_SALT=tobemodified # [SECRET]` (the `tobemodified`/`# [SECRET]` convention; token ABSENT)
- `docs/SECRETS_ROTATION_REQUIRED.md:23` — `STRAPI_API_TOKEN_INTERNAL` already in the secrets inventory (P1)
- `scripts/preflight.sh:6-24,61-67` — `REQ_VARS` loop → `❌ Missing env` + `exit 1` (the fail-fast extension point); `scripts/env_sync_check.sh:9-53` — `.env.example`↔prod diff
- `.gitleaks.toml:50-87` — `config/.env.example`/`example` allowlisted (placeholder token is safe to commit)
- `.github/workflows/phase-19-assertions.yml:63-102,140-199` — CI mirror: `redis:7-alpine` service, `setup-node node-version '22'` (BLOCKER A), structural grep jobs, `node --test --experimental-strip-types`
- `config/product_modules.json` — module keys (`channel_whatsapp`, `delivery_dispatch`, `order_bot_core`, …) confirming `{module_key}` shape
- `.planning/ROADMAP.md:142-167` (Phase 20 block, success criteria, :147 cache key), `.planning/REQUIREMENTS.md:25,29` (ENT-03, GRD-01)
- Local probes (2026-06-20): `NODE_FUNCTION_ALLOW_EXTERNAL` = **0 hits** repo-wide; `require('ioredis')` in workflows = **0 hits**; `n8n-nodes-base.redis` = **21 workflows**; `/opt/node22/bin/node` v22.22.2, `/usr/bin/jq`, `/usr/bin/redis-server` 7.0.15, `/usr/bin/redis-cli` all present; docker DOWN

### Secondary (MEDIUM confidence — n8n behavior)
- n8n `n8n-nodes-base.redis` GET returns the value as the item (`$json` bare string), SET supports `expire`+`ttl`; `continueOnFail` surfaces a `{error}` item rather than aborting — inferred from consistent repo usage (`W0_CONFIG_READER`, `W0_REDIS_HELPER`, `W1_IN_WA` dedupe-parse) across 21 workflows; behavior to confirm against the pinned n8n 2.9.4 at import/VPS.
- n8n Code-node sandbox blocks non-built-in `require` unless `NODE_FUNCTION_ALLOW_EXTERNAL` lists the module — standard n8n behavior, corroborated by the repo's exclusive use of Redis nodes + built-in-only `require('crypto')`.

### Tertiary (LOW — flagged for validation at import)
- Exact item shape of a `continueOnFail` Redis-node error vs a `continueOnFail` httpRequest error in n8n 2.9.4 (`{error:{message}}` vs `{error:'...'}`): the Decide/Evaluate Code nodes should defensively check both `$json.error` truthiness and (for httpRequest) status — validate at VPS import. The pure seam tests this with explicit mock shapes; the live node shape is the only unverified link.

---

## Metadata

**Confidence breakdown:**
- Redis-access mechanism (Redis nodes, NOT Code-node client): **HIGH** — `NODE_FUNCTION_ALLOW_EXTERNAL`=0 hits + 21-workflow precedent + the `W0_CONFIG_READER` template, all direct-read
- Node topology / cache-aside: **HIGH** — exact mirror of an existing in-repo workflow
- Cache-key + TTL contract: **HIGH** — locked by `audit-hook.ts:122` + ADR 0003, line-cited
- Fail-closed/fall-through matrix: **HIGH** — derived from today's guard semantics + the locked criteria; isolated into a testable seam
- ENT-03 gap + fix: **HIGH** — the absence in both composes + `.env.example` and the presence in the secrets inventory are all grep-verified; `${VAR:?}` + preflight are established idioms
- Alert split: **MEDIUM-HIGH** — distinct reason prefixes + `security_events` severity + `W8_OPS` webhook all exist; the exact wiring point (caller vs guard) is the only open design choice (O-3)
- Validation architecture (pure seam, node --test, jq, ephemeral redis): **HIGH** — all tooling host-verified; the "0 fetches on hit" assertion is a pure-function call-count test
- n8n node runtime item shapes (continueOnFail error envelope): **MEDIUM** — consistent repo usage; final confirmation deferred to VPS import (tertiary source)

**Research date:** 2026-06-20
**Valid until:** 2026-07-20 (stable — the cache key is ROADMAP/ADR-locked, the compose/env/preflight files and the `W0_CONFIG_READER` template are static, the pinned Node/Redis/n8n versions don't move within the milestone)

---

## RESEARCH COMPLETE

**Phase:** 20 — Redis-Cached Fail-Closed Guard + Internal Token Provisioning
**Confidence:** HIGH

### Key Findings
- **THE Redis-access mechanism is `n8n-nodes-base.redis` GET/SET nodes wired AROUND the Code node — NOT a Code-node `ioredis` client.** `NODE_FUNCTION_ALLOW_EXTERNAL` is set NOWHERE in the repo (0 hits) and no Code node does `require('ioredis')` (0 hits); the repo's entire Redis pattern is the Redis node (21 workflows), and `W0_CONFIG_READER.json` is a ready-made cache-aside template to copy (GET→Code→IF→Strapi-fetch→SET).
- **The cache key, ≤5-min positive TTL, and Phase-19 coupling are already LOCKED** by `audit-hook.ts:122` + ADR 0003 — Phase 20 is the POPULATE/READ half. Cache the **raw row + fetchedAt** (re-evaluate `expires_at` on read), negative-cache `NO_ENTITLEMENT` at a shorter TTL, and **NEVER cache a transient `GUARD_ERROR_FAILCLOSED`**. Redis error → fall through to Strapi; Strapi error → DENY; LRU eviction → live query (never a spurious deny).
- **ENT-03 gap is concrete:** `STRAPI_API_TOKEN_INTERNAL` (and `STRAPI_API_URL`) are read by the guard but wired into NEITHER compose's n8n env NOR `.env.example`; the secrets inventory (`docs/SECRETS_ROTATION_REQUIRED.md:23`) already lists it. Fix = compose `${VAR:?msg}` (precedent at `:94-101`) + `.env.example` + extend `scripts/preflight.sh` `REQ_VARS` + a CI negative test.
- **Alert split** keys off the already-distinct reason prefixes: `GUARD_ERROR_FAILCLOSED*` → `security_events` HIGH + `W8_OPS` `ALERT_WEBHOOK_URL` (pageable); `NO_ENTITLEMENT*`/`EXPIRED*`/`MODULE_NOT_FOUND*` → LOW (not paged). Recommend a downstream-only classifier (`classify-deny.mjs`) so 20-03 never touches the guard file.
- **`redis-server` (7.0.15) + `redis-cli` + Node 22.22.2 + `jq` are ALL local** (`/usr/bin`, `/opt/node22/bin`). Validation = a pure `.mjs` decision seam + `node --test` proving "hit → 0 Strapi fetches" + jq structural assertions on `W0_MODULE_GUARD.json` + a preflight negative test — all docker-free.

### File Created
`.planning/phases/20-redis-cached-fail-closed-guard-and-internal-token-provisioning/20-RESEARCH.md`

### Decided Redis-access mechanism (node topology)
`Start → Guard Input Validate (Code) → Redis GET (continueOnFail) → Decide-from-cache (Code) → IF cacheUsable → [HIT: Return Cached — 0 Strapi nodes] | [MISS/Redis-err: Strapi httpRequest ×2 → Evaluate live (Code, fail-closed) → IF cacheable → Redis SET (expire+ttl) → Return]`. Mirrors `W0_CONFIG_READER.json`. Credential = repo placeholder `"id":"REDIS_CREDENTIAL_ID","name":"Redis"` (live id `43SDqJYMGa6RvFqW`).

### Confidence Assessment
| Area | Level | Reason |
|------|-------|--------|
| Redis-access mechanism (nodes not Code client) | HIGH | `NODE_FUNCTION_ALLOW_EXTERNAL`=0 + 21-workflow precedent + template |
| Node topology / cache contents / TTLs | HIGH | exact `W0_CONFIG_READER` mirror; key/TTL locked by ADR 0003 |
| Fail-closed/fall-through matrix | HIGH | derived from today's guard + criteria, isolated to a testable seam |
| ENT-03 gap + fix | HIGH | absence in composes/.env.example + presence in inventory all grep-verified |
| Alert split wiring point | MEDIUM-HIGH | infra exists; caller-vs-guard boundary is the open choice (O-3) |
| n8n continueOnFail error item shape | MEDIUM | consistent repo usage; confirm at VPS import |

### Open Questions (sensible defaults proposed)
1. O-1: Strapi fetch as httpRequest nodes vs in-Code `fetch()` on miss branch → recommend **httpRequest nodes** (jq-verifiable "0 on hit").
2. O-2: hard `${VAR:?}` vs soft `${VAR:-}` → recommend **hard on prod, soft+preflight on base/dev**.
3. O-3: alert-split boundary → recommend **downstream-only classifier** (20-03 never touches the guard).
4. O-4: TTL values → recommend `ENTITLEMENT_CACHE_TTL_SEC=300` / `ENTITLEMENT_NEG_CACHE_TTL_SEC=60` (env-tunable).
5. O-5: whether `preflight-prod.sh` also needs the token → read both during planning; add to `preflight.sh` (the CI-tested one).

### Ready for Planning
Proposed **3 plans**, disjoint file ownership:
- **20-01** — `workflows/W0_MODULE_GUARD.json` cache-aside restructure (Redis GET/SET nodes + IF branches + the two Strapi fetches on the miss branch) + `scripts/guard/entitlement-decision.mjs` (pure seam) + its `node --test` + the structural-jq half of `phase-20-assertions.yml` + `scripts/test-phase20.sh`. **ONLY plan touching the guard JSON.**
- **20-02** — `STRAPI_API_TOKEN_INTERNAL` (+`STRAPI_API_URL` + TTL vars) in `docker-compose.hostinger.prod.yml` (`${VAR:?}`) + `docker-compose.base.yml` (soft) + `config/.env.example` + annotate `docs/SECRETS_ROTATION_REQUIRED.md` + extend `scripts/preflight.sh` REQ_VARS + the ENT-03 grep/negative-test CI job. **NO workflow edits.**
- **20-03** — `scripts/guard/classify-deny.mjs` (reason→severity) + its `node --test` + downstream alert wiring (`security_events` severity / `W8_OPS` `ALERT_WEBHOOK_URL` keyed off the FAILCLOSED prefix) + the classifier CI job. **Keys off the guard's stable reason prefixes — no guard-topology edits.**

**🔴 VPS deferred:** import the restructured `W0_MODULE_GUARD.json` (wires `REDIS_CREDENTIAL_ID`→live cred), provision the real `STRAPI_API_TOKEN_INTERNAL`, confirm guard Redis == Phase-19 DEL Redis, confirm prod `allkeys-lru`/maxmemory policy.
