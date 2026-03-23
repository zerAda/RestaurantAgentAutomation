---
phase: 02-structured-logging-and-correlation
plan: "03"
subsystem: infra
tags: [strapi, pino, logging, json, ndjson, middleware, async-local-storage]

requires: []
provides:
  - Strapi Pino logger emits structured NDJSON in production
  - X-Request-ID propagated into all Strapi log entries via AsyncLocalStorage
  - global::request-id middleware registered before strapi::logger
affects:
  - 02-04-smoke-correlation

tech-stack:
  added: []
  patterns:
    - "AsyncLocalStorage for request-scoped context propagation across Pino log calls"
    - "Strapi config/logger.ts overrides default pretty-print with custom Pino formatters"

key-files:
  created:
    - inventory-cms/config/logger.ts
    - inventory-cms/src/middlewares/request-id.ts
  modified:
    - inventory-cms/config/middlewares.ts

key-decisions:
  - "Used AsyncLocalStorage (not ctx state) so request_id is available in service/controller code without ctx"
  - "Inlined ISO timestamp function to avoid depending on pino type declarations (pino is transitive dep)"
  - "global::request-id registered as FIRST middleware in middlewares.ts to ensure it runs before logger"

patterns-established:
  - "Strapi request correlation: AsyncLocalStorage in request-id.ts, read in logger.ts formatters.log"
  - "Strapi JSON logging: config/logger.ts with formatters.level + formatters.log + timestamp overrides"

requirements-completed:
  - OBS-02
  - OBS-04

duration: 8min
completed: 2026-03-23
---

# Plan 02-03: Strapi Pino Structured Logging Summary

**Pino JSON logger config + AsyncLocalStorage request-id middleware — Strapi now emits NDJSON with correlation IDs**

## Performance

- **Duration:** ~8 min
- **Completed:** 2026-03-23
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created `inventory-cms/config/logger.ts` — Pino formatter emitting `{level, msg, time, service, request_id}` in production
- Created `inventory-cms/src/middlewares/request-id.ts` — Koa middleware extracting `X-Request-ID` into AsyncLocalStorage
- Updated `inventory-cms/config/middlewares.ts` — `global::request-id` registered as first middleware, before `strapi::logger`

## Task Commits

1. **Task 1+2: Add request-id middleware and Pino JSON logger** - `0ff48c7` (feat)

## Files Created/Modified
- `inventory-cms/config/logger.ts` — Structured JSON logging with request_id binding
- `inventory-cms/src/middlewares/request-id.ts` — X-Request-ID extraction via AsyncLocalStorage
- `inventory-cms/config/middlewares.ts` — `global::request-id` registered as first middleware

## Decisions Made
- Used `AsyncLocalStorage` rather than passing ctx through call stack — cleaner, works in service layer
- Used inline ISO function to avoid pino peer-dependency issues in TypeScript compilation
- `global::request-id` placed FIRST in middleware array to guarantee it runs before logger captures request_id

## Deviations from Plan
None — all three artifacts match plan specification exactly.

## Issues Encountered
None.

## Next Phase Readiness
- Strapi NDJSON logs with request_id ready for correlation trace in 02-04
- CMS container rebuild required on VPS to activate TypeScript changes

---
*Phase: 02-structured-logging-and-correlation*
*Completed: 2026-03-23*
