# Strapi CMS Codebase Concerns

**Analysis Date:** 2026-03-20

## Tech Debt

### Duplicate Agent Chat Implementation

**Area:** `src/api/system-config/controllers/agent-chat.ts` vs `src/extensions/agent-chat/controllers/agent-chat.ts`

- Issue: Two complete agent-chat controller implementations exist, both registered for `POST /api/agent/chat`. The system-config version has `auth: false` + manual JWT validation. The extensions version has scope-based auth via `src/index.ts register()`. Both forward to different n8n webhook paths (`/webhook/admin/chat` vs `/webhook/admin-agent`).
- Files:
  - `src/api/system-config/controllers/agent-chat.ts` (Redis RAG, 16 context slices, full implementation)
  - `src/extensions/agent-chat/controllers/agent-chat.ts` (simpler version)
  - `src/api/system-config/routes/agent-chat.ts` (registers route with `auth: false`)
  - `src/extensions/agent-chat/routes/agent-chat.ts` (registers route with scope auth)
  - `src/index.ts` (also programmatically registers `/api/agent/chat` via `strapi.server.routes()`)
- Impact: Three registrations of the same route path. In Strapi 5, last-registered wins. The actual behavior in production is non-deterministic and depends on registration order. One implementation silently shadows the other.
- Fix approach: Remove one implementation. The system-config version is more complete (Redis RAG, rate limiting, session memory). Delete `src/extensions/agent-chat/` and remove the `register()` call in `src/index.ts`.

---

### In-Memory Rate Limiter Resets on Restart

**Area:** `src/middlewares/auth-ratelimit.ts`

- Issue: `authHits` and `apiHits` are in-process `Map` objects. All rate limit state is lost every time Strapi restarts. An attacker can force unlimited login attempts by triggering a restart (or waiting for a deploy).
- Files: `src/middlewares/auth-ratelimit.ts` (documented with comment `[C-04]`)
- Impact: Brute force protection window is < restart interval, not 5 minutes as intended. An OOM or deploy-triggered restart resets the counter.
- Fix approach: Migrate to Redis-backed counters using the existing ioredis dependency. The agent-chat controller already implements Redis rate limiting as a pattern (`checkRateLimit` function) — apply the same pattern to auth-ratelimit middleware.

---

### Webhook Idempotency Service Uses `strapi.cache` (In-Memory)

**Area:** `src/extensions/webhook-idempotency/services/idempotency.ts`

- Issue: `strapi.cache` is Strapi's in-memory cache layer. On container restart, all idempotency keys are lost. During the 5-minute TTL window after a restart, WhatsApp webhook retries will be processed as new messages (triple-processing).
- Files: `src/extensions/webhook-idempotency/services/idempotency.ts`
- Impact: Duplicate order creation, duplicate LLM calls, duplicate customer messages during any restart event.
- Fix approach: Use Redis directly (ioredis already imported elsewhere) with `SETEX` for the 5-min TTL. Same pattern as the RAG cache in `src/api/system-config/controllers/agent-chat.ts`.

---

### Prometheus Metrics In-Memory (Resets on Restart)

**Area:** `src/middlewares/prometheus-tracker.ts`

- Issue: `requestCounters` and `latencyBuckets` are module-level objects. Metrics reset to zero on every Strapi restart. P95/P99 buckets are capped at last 1000 requests per route but not persisted.
- Files: `src/middlewares/prometheus-tracker.ts`
- Impact: No historical trend data. Any monitoring system scraping `/api/metrics` sees counter reset after deploys, making anomaly detection unreliable.
- Fix approach: Ship metrics to an external collector (Prometheus remote write, or publish to a Redis time-series). For now, accept the limitation and add a restart annotation mechanism.

---

### `platform-setting` Content Type Has Wrong Default for `category`

**Area:** `src/api/platform-setting/content-types/platform-setting/schema.json`

- Issue: The `category` field is an enumeration with values `["CORE","AI","SOCIAL","LOGISTICS","WEB_KIOSK","WEB_ADMIN","PAYMENT","SECURITY"]` but the `default` is set to `"ops"` — which is not in the enum. This will cause a Strapi validation error when creating a `platform-setting` without explicitly providing a category.
- Files: `src/api/platform-setting/content-types/platform-setting/schema.json` line 44
- Impact: Any n8n or API call that creates a platform-setting entry without `category` will receive a validation error. Strapi admin panel form will not populate a valid default.
- Fix approach: Change `"default": "ops"` to `"default": "CORE"` in the schema, then rebuild image.

---

### `system-config` Has 100+ Fields Including Private Tokens Stored in Database

**Area:** `src/api/system-config/content-types/system-config/schema.json`

- Issue: `whatsapp_access_token`, `facebook_page_token`, `instagram_access_token`, `chargily_secret_key`, `tiktok_ads_access_token`, and 15+ other secrets are stored as `private: true` Strapi fields in the `system_configs` database table. `private: true` only hides them from API responses — they are still stored in plaintext in PostgreSQL.
- Files: `src/api/system-config/content-types/system-config/schema.json`
- Impact: A database dump, a SQL injection, or a misconfigured permission exposing the admin API token would leak production API keys for WhatsApp, Facebook, Instagram, TikTok, and payment processor.
- Fix approach: Migrate API keys from the `system-config` database table to Docker secrets or environment variables. Keep only non-secret configuration fields in the CMS. Reference secrets by env var name in the CMS schema instead of storing the value.

---

### `delivery-config` and `delivery-zone` Overlap

**Area:** `src/api/delivery-config/` and `src/api/delivery-zone/`

- Issue: Both content types represent delivery zone configuration with overlapping fields (`zone_name`/`name`, pricing, ETA, active flag). `delivery-config` is more complete (polygon GeoJSON, per-km fees, schedule JSON). `delivery-zone` schema was not read but appears to be an earlier simpler version.
- Files: `src/api/delivery-config/content-types/delivery-config/schema.json`, `src/api/delivery-zone/content-types/delivery-zone/schema.json`
- Impact: n8n workflows and admin dashboard may read from one or the other inconsistently. Redundant data maintenance.
- Fix approach: Consolidate to `delivery-config` (more complete schema). Migrate any data from `delivery-zone` and remove the duplicate.

---

## Known Bugs

### `POST /api/agent/chat` Route Registered Three Times

- Symptoms: Non-deterministic behavior for admin chat — sometimes uses Redis RAG implementation, sometimes uses simpler extensions implementation
- Files: `src/index.ts`, `src/api/system-config/routes/agent-chat.ts`, `src/extensions/agent-chat/routes/agent-chat.ts`
- Trigger: Every Strapi startup registers all three route sources
- Workaround: The system-config routes directory implementation is likely winning because API directory routes are loaded before extension routes, but this is not guaranteed by documentation

---

### `platform-setting` Enum Default Mismatch

- Symptoms: `Validation error: category must be one of CORE, AI, SOCIAL, LOGISTICS, WEB_KIOSK, WEB_ADMIN, PAYMENT, SECURITY` when creating a platform-setting via n8n without a category
- Files: `src/api/platform-setting/content-types/platform-setting/schema.json`
- Trigger: `POST /api/platform-settings` without `data.category` field

---

## Security Considerations

### Secrets Stored in Database

- Risk: 15+ API tokens/secrets stored in `system_configs` PostgreSQL table via system-config singleType
- Files: `src/api/system-config/content-types/system-config/schema.json` (fields with `"private": true`)
- Current mitigation: `private: true` hides from REST API responses; IP allowlist protects CMS; admin API token required
- Recommendations: Move secrets to Docker secrets or environment variables; only store non-sensitive config in CMS database

### `POST /api/agent/chat` Uses `auth: false` + Manual JWT Validation

- Risk: Manual JWT validation in controller can have edge cases the Strapi auth layer handles correctly
- Files: `src/api/system-config/routes/agent-chat.ts` (`auth: false`), `src/api/system-config/controllers/agent-chat.ts`
- Current mitigation: Controller verifies JWT via `strapi.plugin('users-permissions').service('jwt').verify(token)`, checks user existence
- Recommendations: Switch to Strapi-native auth and validate user inside controller if additional checks needed, rather than disabling Strapi auth entirely

### `GET /api/realtime/orders/stream` (SSE) Uses Token in Query String

- Risk: `?token=...` query parameter for SSE auth — tokens in URLs are logged by nginx, appear in browser history, and in `Referer` headers
- Files: `src/api/realtime/routes/realtime.ts` (comment confirms this), `src/api/realtime/controllers/realtime.ts`
- Current mitigation: The route is behind Traefik's admin subdomain IP allowlist; only admin users can reach it
- Recommendations: EventSource API limitation acknowledged; consider WebSocket as alternative for authenticated real-time if token-in-URL is unacceptable

### Rate Limiting Bypassed by Restart

- Risk: Auth brute-force protection resets on container restart
- Files: `src/middlewares/auth-ratelimit.ts`
- Current mitigation: Traefik IP allowlist blocks non-authorized IPs from reaching admin/cms; n8n trusted IP exemption is explicit
- Recommendations: Redis-backed rate limiting (priority fix)

---

## Performance Bottlenecks

### Agent Chat RAG Fetches Spawn Parallel DB Queries

- Problem: Agent chat detects up to 16 context slices and launches all fetches in parallel (`Promise.all`). Each slice queries a different content type. Under load with slow queries, this creates 16 concurrent DB connections.
- Files: `src/api/system-config/controllers/agent-chat.ts` (lines 372-376)
- Cause: No concurrency limit on `Promise.all`. Each slice calls `strapi.db.query` which uses the Knex connection pool (max 10).
- Improvement path: Add `p-limit` or manual batching for slice fetches. Increase `DATABASE_POOL_MAX` if needed. Redis caching (already implemented, 5 min TTL) reduces repeat fetches.

### `config/api.ts` maxLimit of 10,000

- Problem: Any authenticated caller can request up to 10,000 records in a single API call
- Files: `config/api.ts` (`maxLimit: 10000`)
- Cause: Originally set high for n8n bulk data retrieval
- Improvement path: Lower to 1,000 with explicit pagination. Add n8n service account exemption or chunked fetch pattern in workflows.

---

## Fragile Areas

### `src/index.ts` bootstrap() — Admin User Sync

- Files: `src/index.ts`
- Why fragile: Creates admin user and updates Users-Permissions user password on every Strapi startup. If `STRAPI_SUPER_ADMIN_PASSWORD` is undefined or empty, it writes an empty password to the API user (`upRepo.update` runs unconditionally for existing users at line 126-130).
- Safe modification: Always ensure `STRAPI_SUPER_ADMIN_PASSWORD` is set in environment before adding new bootstrap logic. The update-always pattern (not update-if-changed) means any misconfigured env var immediately overwrites the production password.
- Test coverage: None

### Custom Route Registration in `src/index.ts` register()

- Files: `src/index.ts` (lines 10-54)
- Why fragile: `strapi.controller()` and `strapi.server.routes()` are called with `require()` (CommonJS), but the project compiles to ESM. This works at runtime because dist files are CommonJS-compatible through the build, but is not idiomatic. The try/catch suppresses any registration failure with only a `console.warn`.
- Safe modification: Verify the dist compilation mode before changing this pattern. The graceful degradation comment ("routes may already be registered via api/ directory") masks the real behavior.
- Test coverage: None

### Realtime SSE Service — Module-Level Redis Singletons

- Files: `src/api/realtime/services/realtime.ts`
- Why fragile: `redisPub` and `redisSub` are module-level `let` variables. If either Redis connection drops and is replaced, the old singleton reference is leaked. The `bootstrap()` subscribes to `order_updates` channel but there is no reconnect logic.
- Safe modification: Do not call `getRedisSubscriber()` more than once per server lifecycle. Test Redis reconnection behavior before relying on SSE for production order tracking.
- Test coverage: None

---

## Scaling Limits

**Database Connection Pool:**
- Current capacity: min 2, max 10 connections per Strapi instance
- Limit: 10 simultaneous DB queries — agent chat RAG alone can exhaust this (16 parallel queries)
- Scaling path: Increase `DATABASE_POOL_MAX` env var. Consider PgBouncer for connection pooling if multiple Strapi instances are run.

**In-Memory Prometheus Metrics:**
- Current capacity: Last 1,000 requests per route group (latency buckets)
- Limit: Memory bounded but not persisted
- Scaling path: External Prometheus scrape + Grafana

---

## Dependencies at Risk

### `@strapi/plugin-cloud` 5.37.1 (present but unused)

- Risk: Adds ~bundle size to image; any vulnerability in this plugin affects the CMS
- Impact: No direct impact if unused, but it still runs initialization code
- Migration plan: Remove from `package.json` if Strapi Cloud deployment is confirmed as not needed

### `zod` ^4.3.6 (minor version mismatch with ecosystem)

- Risk: zod v4 is a significant API change from v3. Most Strapi community resources reference v3. Verify any custom validation code uses v4 API.
- Files: `package.json`
- Impact: Low — only used in custom code, not by Strapi itself

---

## Missing Critical Features

### No File Upload Cloud Storage

- Problem: Strapi media uploads go to `public/uploads/` inside the container volume (local filesystem). Container recreation or deployment will cause upload loss unless a persistent volume is configured.
- Blocks: Any product image or creative asset uploaded via Strapi admin is at risk of loss on redeploy
- Fix: Configure `@strapi/provider-upload-local` with a Docker volume mount, or migrate to `@strapi/provider-upload-aws-s3`

### No Strapi Webhook Outbound Configuration

- Problem: Strapi webhooks (`webhooks.populateRelations` is in config but no outbound webhooks are defined for content type lifecycle events). n8n cannot receive real-time notifications when a product is updated in the CMS admin.
- Blocks: n8n workflows must poll Strapi instead of reacting to changes
- Fix: Configure outbound webhooks in Strapi Admin > Settings > Webhooks pointing to n8n webhook endpoint

---

## Test Coverage Gaps

### Zero Automated Tests

- What's not tested: All controllers (agent-chat, inbound-message, metric, realtime, control-plane), all middleware (auth-ratelimit, prometheus-tracker, admin-cookie-auth), bootstrap logic, idempotency service
- Files: Entire `src/` directory — no `*.test.ts` or `*.spec.ts` files found
- Risk: Any regression in rate limiting, auth validation, or agent chat will only be caught in production
- Priority: High — especially for `auth-ratelimit.ts` (security) and agent-chat controller (business-critical)

### No Integration Tests for Critical Flows

- What's not tested: Full agent-chat request cycle (JWT validation → RAG → n8n forward → response), idempotency dedup under concurrent requests, SSE stream teardown
- Priority: High

---

*Concerns audit: 2026-03-20*
