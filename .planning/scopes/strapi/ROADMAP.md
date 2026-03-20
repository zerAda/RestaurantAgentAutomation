# Strapi CMS Scope — ROADMAP

**Scope:** `project/inventory-cms/`
**Analysis date:** 2026-03-20
**Platform:** RESTO BOT v3.3.0 — Strapi 5.37.1 on VPS

---

## Context

Strapi is the central config hub for the entire platform. All services (n8n, admin-dashboard, kiosk-app, gateway) depend on it. Bugs here degrade the entire platform. This roadmap addresses known defects and security risks before adding features.

---

## Phase Ordering Rationale

| # | Phase | Why this order |
|---|-------|----------------|
| 1 | Stability — route dedup + enum bug | Crashes and non-deterministic behavior affect every restart |
| 2 | Security — secrets migration + Redis rate limiting | Secrets in DB are an active risk; brute-force window is broken |
| 3 | Reliability — Redis idempotency + bootstrap hardening | Duplicate order creation on restart is a data integrity issue |
| 4 | Data integrity — permission matrix audit + maxLimit | Incorrect permissions allow over-exposure or block legitimate calls |
| 5 | Features — media cloud storage + outbound webhooks | Operational improvements once the platform is stable |
| 6 | Testing — integration + contract tests | Locks in regressions after all above changes |

---

## Phase 1: Stability — Route Deduplication and Schema Bug Fixes

**Goal:** Every Strapi restart produces deterministic behavior. No invalid schema defaults. No silent route shadowing.

**Requirements:** STBL-01, STBL-02, STBL-03

**Success criteria:**
- `POST /api/agent/chat` is registered exactly once, using the Redis-RAG implementation in `src/api/system-config/`
- `src/extensions/agent-chat/` directory is removed; `src/index.ts` `register()` block no longer calls `strapi.server.routes()` for agent-chat
- `src/index.ts` `register()` is a no-op or removed entirely once no extension routes remain
- `platform-setting` schema `category` default is `"CORE"` (a valid enum value)
- `POST /api/platform-settings` without a `category` field succeeds with default `"CORE"`
- CMS image rebuilds cleanly with zero TypeScript errors
- Strapi starts in < 90 seconds and `/health` returns 204

**Requirements detail:**

| ID | Requirement |
|----|-------------|
| STBL-01 | Remove `src/extensions/agent-chat/` entirely and remove the agent-chat `strapi.server.routes()` call from `src/index.ts register()` so `POST /api/agent/chat` is registered exactly once |
| STBL-02 | Fix `platform-setting` schema: change `"default": "ops"` to `"default": "CORE"` in `src/api/platform-setting/content-types/platform-setting/schema.json` |
| STBL-03 | Verify `src/index.ts register()` has no remaining dead code after agent-chat extension removal; clean up or remove the hook if empty |

**Plans:** 2 plans

Plans:
- [ ] 01-PLAN.md — Remove duplicate agent-chat extension + clean up register() lifecycle hook
- [ ] 02-PLAN.md — Fix platform-setting enum default + validate schema correctness

---

## Phase 2: Security — Secrets Migration and Redis-Backed Rate Limiting

**Goal:** No production API keys stored in the PostgreSQL `system_configs` table. Auth rate limiting survives container restarts.

**Requirements:** SEC-01, SEC-02, SEC-03

**Success criteria:**
- All 15+ channel token fields (`whatsapp_access_token`, `facebook_page_token`, `instagram_access_token`, `chargily_secret_key`, `tiktok_ads_access_token`, etc.) are removed from `system-config` schema
- Equivalent env var reference fields (e.g. `whatsapp_access_token_env_var`) are added to guide operators where to set each secret
- `src/middlewares/auth-ratelimit.ts` uses ioredis `INCR`/`EXPIRE` counters instead of in-process Maps
- After a Strapi container restart during a rate-limit window, `authHits` state is preserved in Redis
- CMS image rebuilds cleanly; all existing automated smoke tests pass

**Requirements detail:**

| ID | Requirement |
|----|-------------|
| SEC-01 | Remove the 15+ `private: true` secret fields from `src/api/system-config/content-types/system-config/schema.json`; add documentation-only string fields indicating which env var holds each secret |
| SEC-02 | Update `src/api/system-config/controllers/agent-chat.ts` `CONFIG_ALLOWED_FIELDS` to remove the now-deleted secret fields |
| SEC-03 | Rewrite `src/middlewares/auth-ratelimit.ts` to use ioredis `INCR` + `EXPIRE` (pattern already established in the agent-chat controller) instead of the in-process `authHits` and `apiHits` Maps |

**Plans:** 2 plans

Plans:
- [ ] 03-PLAN.md — Remove plaintext secrets from system-config schema; update CONFIG_ALLOWED_FIELDS
- [ ] 04-PLAN.md — Rewrite auth-ratelimit middleware to use Redis-backed counters

---

## Phase 3: Reliability — Redis Idempotency and Bootstrap Hardening

**Goal:** Webhook deduplication survives Strapi restarts. Bootstrap cannot overwrite passwords with empty strings.

**Requirements:** REL-01, REL-02, REL-03

**Success criteria:**
- `src/extensions/webhook-idempotency/services/idempotency.ts` uses Redis `SETEX` instead of `strapi.cache`
- WhatsApp webhook retries arriving within 5 minutes of a restart are correctly identified as duplicates
- `src/index.ts bootstrap()` guards against `STRAPI_SUPER_ADMIN_PASSWORD` being undefined/empty before calling `upRepo.update`
- Bootstrap logs a clear `WARN` and skips the password update if the env var is missing
- Realtime SSE service Redis singleton is wrapped with a reconnect guard

**Requirements detail:**

| ID | Requirement |
|----|-------------|
| REL-01 | Rewrite idempotency service to use `redis.setex(key, 300, '1')` / `redis.get(key)` pattern, same ioredis instance used elsewhere |
| REL-02 | Add guard in `src/index.ts bootstrap()`: `if (!password || password.trim() === '') { strapi.log.warn('STRAPI_SUPER_ADMIN_PASSWORD not set — skipping API user password update'); return; }` |
| REL-03 | Add reconnect event handlers to `redisPub`/`redisSub` in `src/api/realtime/services/realtime.ts` so dropped Redis connections are re-subscribed to `order_updates` |

**Plans:** 2 plans

Plans:
- [ ] 05-PLAN.md — Migrate idempotency service to Redis SETEX
- [ ] 06-PLAN.md — Harden bootstrap password guard + realtime Redis reconnect

---

## Phase 4: Data Integrity — Permission Matrix Audit and API Limit

**Goal:** Public and Authenticated role permissions match the documented contract. Bulk API calls cannot return 10,000 rows by default.

**Requirements:** DATA-01, DATA-02, DATA-03

**Success criteria:**
- Bootstrap `bootstrap()` programmatically verifies and audits the Public role has exactly `product.find` and `product.findOne` (warns if more)
- Authenticated role permissions list is codified in a fixture and checked at bootstrap
- `config/api.ts` `maxLimit` lowered from 10,000 to 1,000
- `delivery-zone` and `delivery-config` overlap is documented with a consolidation migration plan
- n8n bulk-fetch workflows use paginated requests (`_start` / `_limit`) rather than relying on `maxLimit`

**Requirements detail:**

| ID | Requirement |
|----|-------------|
| DATA-01 | Lower `config/api.ts` `maxLimit` from 10,000 to 1,000 with comment explaining the change |
| DATA-02 | Add codified permission fixture array to `src/index.ts bootstrap()` for Authenticated role; log a `WARN` for any missing permission at startup |
| DATA-03 | Document `delivery-zone` / `delivery-config` overlap in a `DEPRECATION.md` in `src/api/delivery-zone/` and add a migration plan comment |

**Plans:** 2 plans

Plans:
- [ ] 07-PLAN.md — Lower maxLimit; codify Authenticated role permission fixture in bootstrap
- [ ] 08-PLAN.md — Document delivery-zone deprecation; add delivery-config migration note

---

## Phase 5: Features — Media Cloud Storage and Outbound Webhooks

**Goal:** Uploads survive container recreation. n8n can react to CMS changes in real time.

**Requirements:** FEAT-01, FEAT-02

**Success criteria:**
- `@strapi/provider-upload-aws-s3` (or equivalent) configured and enabled; uploads land in S3/R2, not `public/uploads/`
- `public/uploads/` is no longer the active storage backend in production
- At least 2 outbound Strapi webhooks configured pointing to n8n endpoints: one for `entry.create` on `product`, one for `entry.update` on `order`
- n8n `W_PRODUCT_SYNC` workflow (or equivalent) receives the Strapi webhook payload and processes it without polling

**Requirements detail:**

| ID | Requirement |
|----|-------------|
| FEAT-01 | Configure Strapi upload provider for S3-compatible cloud storage; add `UPLOADS_PROVIDER`, `UPLOADS_BUCKET`, `UPLOADS_REGION`, `UPLOADS_ACCESS_KEY`, `UPLOADS_SECRET_KEY` env vars to compose and ENV_REFERENCE.md |
| FEAT-02 | Configure at least 2 outbound Strapi webhooks in `config/server.ts` or via admin panel (documented in RUNBOOK.md); add n8n webhook URLs from env vars |

**Plans:** 2 plans

Plans:
- [ ] 09-PLAN.md — Configure S3-compatible upload provider for persistent media storage
- [ ] 10-PLAN.md — Configure outbound Strapi webhooks for real-time n8n event delivery

---

## Phase 6: Testing — Integration and Contract Tests

**Goal:** Zero-regression enforcement for all critical paths: auth, rate limiting, agent-chat, idempotency, permission matrix.

**Requirements:** TEST-01, TEST-02, TEST-03

**Success criteria:**
- `src/middlewares/auth-ratelimit.test.ts` exists with tests for: 5-attempt lockout, Redis key TTL, trusted IP exemption
- `src/api/system-config/controllers/agent-chat.test.ts` tests: valid JWT accepted, expired JWT rejected, rate-limit 429 returned at attempt 21
- `src/extensions/webhook-idempotency/services/idempotency.test.ts` tests: first call returns `isDuplicate: false`, same-key second call returns `isDuplicate: true`
- `scripts/test-permissions.sh` script verifies Public role has exactly product.find + findOne and Authenticated role has all required permissions via API calls
- All tests pass in CI (`npm test` in `inventory-cms/`)

**Requirements detail:**

| ID | Requirement |
|----|-------------|
| TEST-01 | Unit tests for auth-ratelimit middleware (mock ioredis) and idempotency service (mock ioredis) |
| TEST-02 | Integration tests for agent-chat controller covering JWT validation edge cases and rate-limit enforcement |
| TEST-03 | Smoke script `scripts/test-permissions.sh` that calls Strapi API with and without auth to verify the permission matrix |

**Plans:** 2 plans

Plans:
- [ ] 11-PLAN.md — Unit tests: auth-ratelimit + idempotency service
- [ ] 12-PLAN.md — Integration tests: agent-chat + permission matrix smoke script

---

*Roadmap version: 1.0 — 2026-03-20*
