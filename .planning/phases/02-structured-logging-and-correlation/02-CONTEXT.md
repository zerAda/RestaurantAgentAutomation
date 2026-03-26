# Phase 02 Context — Structured Logging & Correlation

**Phase:** 02 — Structured Logging & Correlation
**Created:** 2026-03-23
**Status:** Planning

---

## Problem Statement

The platform is currently a black box for debugging. When a WhatsApp message triggers a failed
order, there is no way to trace what happened across the three layers it passes through:

1. Nginx gateway logs a request with IP + URI — no identifier to correlate downstream
2. n8n emits unstructured text logs (default Pino text format) that mix workflow ID into free-text
3. Strapi emits default Pino text logs — no request identifier, no JSON fields

When something breaks in production, the investigation involves grepping across three separate
log streams with no shared key. This phase adds that shared key: a correlation ID generated at
the gateway, propagated via `X-Request-ID` header to every upstream service.

---

## Approach

### Why not a centralized log aggregator (Loki/ELK)?

That is Phase 3 (ADVOBS-02 is v2 scope). The foundation this phase builds — structured JSON logs
with a consistent schema — is what makes aggregation possible. Ship JSON first, aggregate later.

### Why `$request_id` in Nginx (not a custom UUID generator)?

Nginx's `$request_id` (available since 1.11.0, nginx:1.27 in this project) is a 32-character
lowercase hex UUID generated from the system RNG per-request. It is:
- Zero overhead (C-level, no Lua/OpenResty needed)
- Always present (nginx generates it before any location block runs)
- Already unique enough for log correlation (2^128 collision space)

No `map` block or `set_by_lua` needed — `$request_id` is a built-in nginx variable.

### Why Winston JSON for Strapi (not Pino)?

Strapi 5 uses `strapi::logger` middleware which wraps Pino. The official Strapi 5 docs expose a
`config/logger.ts` file that can override the logger transport. Winston is NOT needed — Strapi 5
supports Pino transport options directly in `config/logger.ts`. The plan uses Pino's built-in
`transport.target: 'pino/file'` with `messageKey` and a custom formatter to emit JSON with the
`request_id` field. This avoids adding a new dependency.

### Why a custom Koa middleware for Strapi request ID passthrough?

Strapi's `strapi::logger` middleware does not automatically capture `X-Request-ID` from the
incoming request headers. We add a lightweight global middleware (registered before
`strapi::logger` in `middlewares.ts`) that reads `ctx.request.headers['x-request-id']` and
stores it in `ctx.state.requestId`. The logger config then reads from `ctx.state.requestId` in
the serializer. Strapi's existing `prometheus-tracker.ts` pattern shows this Koa middleware
shape is already established in this codebase.

### n8n structured logging

n8n 2.9.4 supports `N8N_LOG_FORMAT=json` (produces NDJSON to stdout). The `N8N_LOG_LEVEL` and
`N8N_LOG_OUTPUT` env vars complete the configuration. No code changes to n8n itself — pure env
var configuration in `docker-compose.hostinger.prod.yml`.

---

## Deployment Model

All three changes deploy without container recreation for n8n and Strapi (env var changes need
restart, not recreation). Nginx config change requires `nginx -s reload` (zero downtime) or
container recreation for `proxy_params` changes. The plans document the exact VPS commands.

**Zero downtime guarantee:** Nginx reload takes < 1 second. Strapi restart takes ~30 seconds
(health probe monitors recovery). n8n restart takes < 10 seconds.

---

## Plans

| Plan | Change | Requirements | Wave |
|------|--------|--------------|------|
| 02-01 | Nginx: `$request_id` in log format + `X-Request-ID` proxy header | OBS-03, OBS-04 | 1 |
| 02-02 | n8n: `N8N_LOG_FORMAT=json` + structured log env vars | OBS-01 | 1 |
| 02-03 | Strapi: `config/logger.ts` JSON transport + request-id middleware | OBS-02, OBS-04 | 1 |
| 02-04 | Smoke test: end-to-end trace verification script | OBS-01, OBS-02, OBS-03, OBS-04 | 2 |

Plans 01, 02, 03 are independent (touch different files) and can execute in parallel (Wave 1).
Plan 04 depends on all three being deployed and running.

---

## Key Technical Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Request ID source | Nginx `$request_id` built-in | Zero overhead, no deps, present before location blocks |
| n8n log format | `N8N_LOG_FORMAT=json` env var | Supported natively in n8n 2.9.4, no code change |
| Strapi logger | `config/logger.ts` with Pino transport | Official Strapi 5 pattern, no new npm dependency |
| Strapi request ID capture | Koa middleware before `strapi::logger` | Follows existing middleware pattern (prometheus-tracker.ts) |
| Log field name | `request_id` (not `x-request-id`) | Consistent across all three services; searchable |

---

## Files This Phase Touches

```
infra/gateway/nginx.conf           — add $request_id to log_format, X-Request-ID proxy header
infra/gateway/proxy_params         — add proxy_set_header X-Request-ID $request_id
docker-compose.hostinger.prod.yml  — add N8N_LOG_FORMAT, N8N_LOG_LEVEL, N8N_LOG_OUTPUT to n8n-main + n8n-worker
inventory-cms/config/logger.ts     — NEW: Pino JSON transport with request_id serializer
inventory-cms/config/middlewares.ts — prepend global::request-id middleware
inventory-cms/src/middlewares/request-id.ts — NEW: Koa middleware that captures X-Request-ID
scripts/smoke-correlation.sh       — NEW: end-to-end trace verification script
```
