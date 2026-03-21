---
plan: 01-02
phase: 01-cms-stability-and-base-upgrade
status: partial
completed: 2026-03-19
duration: ~4h (blocked by Node.js regression)
---

# Summary: 01-02 — CMS Clean Rebuild

## What Was Built

A fresh `docker compose build cms --no-cache` was executed on the VPS, producing image `44cf772ff9b2` (3.36GB, built 2026-03-18 14:21 UTC) with all Strapi API routes compiled from TypeScript source — eliminating the `docker cp` runtime injection hack.

## Outcome

**Partial** — image built successfully from TS, but blocked before smoke tests.

### Completed
- New CMS image `44cf772ff9b2` built with all routes in `dist/src/api/` (27 APIs, routes from TS)
- Identified root cause of previous CMS failures (docker cp injections)
- Identified and resolved broken CMD in image (previous agent left debug command as CMD)
- Fixed compose file entrypoint/command overrides

### Blocked
- Image fails to start due to **Node.js 20.20.1 ESM regression**: `ERR_UNSUPPORTED_DIR_IMPORT` on `@strapi/core/node_modules/lodash/fp` imported from `Strapi.mjs`
- Old image (v20.20.0) starts but routes return 404 (content types not registered in old image)

## Root Cause

`node:20-alpine` resolved to v20.20.1 at build time. Node.js 20.20.1 tightened ESM directory import resolution — `import 'lodash/fp'` now fails with `ERR_UNSUPPORTED_DIR_IMPORT` when the directory has no `index.js`. Node.js 20.20.0 (old image) allowed it.

## Fix Applied

`project/inventory-cms/Dockerfile`: both stages changed from `node:20-alpine` to `node:20.20.0-alpine` to pin the working version. Next rebuild will produce a working image.

## Key Files

- `project/inventory-cms/Dockerfile` — pinned `node:20.20.0-alpine`
- `project/TEST_REPORT.md` — Phase 1 section updated with actual results
- VPS compose: `entrypoint`/`command` overrides added for cms service (reverted to `npm run start`)

## Next Action

Rebuild the CMS on VPS: `docker compose build cms --no-cache` (15-30 min) — will now use v20.20.0 and succeed. Then re-run `smoke-cms-routes.sh` to complete CMS-02/CMS-03.
