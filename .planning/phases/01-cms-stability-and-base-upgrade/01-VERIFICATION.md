---
phase: 01-cms-stability-and-base-upgrade
verified: 2026-03-19T00:00:00Z
status: gaps_found
score: 3/6 success criteria verified
re_verification: false
gaps:
  - truth: "Running docker compose build cms from a clean state produces an image where all 15 API routes respond correctly — no manual docker cp required"
    status: partial
    reason: "CMS image was rebuilt clean from TS source (image 44cf772ff9b2) confirming routes are baked in, but the rebuilt image fails to start due to a Node.js 20.20.1 ESM regression. A fix was applied (Dockerfile pinned to node:20.20.0-alpine) but the corrected rebuild has not yet run on the VPS. Routes cannot be confirmed as responding correctly until the fix-pinned rebuild completes."
    artifacts:
      - path: "project/inventory-cms/Dockerfile"
        issue: "Fix is in place (node:20.20.0-alpine pinned, commits 2cec0a2 + 5e747b0), but corrected docker compose build cms --no-cache has not run yet — smoke results are BLOCKED in TEST_REPORT.md"
    missing:
      - "Execute docker compose build cms --no-cache on VPS using node:20.20.0-alpine Dockerfile"
      - "Verify new container starts (/_health returns 204)"
      - "Run smoke-cms-routes.sh against freshly started container and record PASS results"

  - truth: "A freshly started CMS container returns expected HTTP status codes on all 15 routes without any post-start injection"
    status: failed
    reason: "The rebuilt image (44cf772ff9b2) fails to start; the running container (19101238eeb3) uses the OLD pre-TS-source image and its routes still return 404 for the 15 custom content types. No verified post-rebuild route check exists in TEST_REPORT.md — the smoke rows are marked BLOCKED."
    artifacts:
      - path: "project/TEST_REPORT.md"
        issue: "Smoke test rows for 'All 15 CMS routes return 200' and 'Admin login + kiosk products' are marked BLOCKED, not PASS"
    missing:
      - "Complete the fix-pinned rebuild (unblocks this truth automatically)"
      - "Run bash project/scripts/smoke-cms-routes.sh and record results"
      - "Replace BLOCKED rows in TEST_REPORT.md Phase 1 section with actual PASS/FAIL counts"

  - truth: "Admin dashboard and kiosk-app Dockerfiles reference node:20-alpine; rebuilt images pass login and product-display smoke checks"
    status: partial
    reason: "Static Dockerfile check PASSES (both use node:20-alpine AS build). However INFRA-03 functional verification (admin login + kiosk products working in rebuilt containers) is explicitly marked DEFERRED in TEST_REPORT.md Phase 1 Summary, blocked on the CMS rebuild completing first."
    artifacts:
      - path: "project/TEST_REPORT.md"
        issue: "INFRA-03 row marked DEFERRED — smoke-post-rebuild.sh has not been run successfully against the current stack"
    missing:
      - "After CMS rebuild completes: run bash project/scripts/smoke-post-rebuild.sh"
      - "Update TEST_REPORT.md INFRA-03 row from DEFERRED to PASS/FAIL with actual output"

human_verification:
  - test: "Run docker compose build cms --no-cache on VPS (after confirming 10GB free disk), wait for healthy container, run smoke-cms-routes.sh"
    expected: "All 15 routes return PASS (200); smoke script exits 0; CMS/_health returns 204"
    why_human: "Requires SSH to VPS at 72.60.190.192; build takes 15-30 minutes; cannot verify programmatically from local machine"
  - test: "Run smoke-post-rebuild.sh after CMS rebuild completes"
    expected: "PASS CMS health (204), PASS CMS login (JWT obtained), PASS kiosk products via gateway (200, data present), PASS admin login via gateway (200, JWT) — Results: 4/4 passed"
    why_human: "Requires live VPS with rebuilt CMS container and working gateway; network-dependent"
---

# Phase 1: CMS Stability & Base Upgrade — Verification Report

**Phase Goal:** The CMS build is self-contained; all 15 Strapi API routes exist in TypeScript source and survive any container rebuild; all frontend Dockerfiles use a supported Node.js LTS

**Verified:** 2026-03-19
**Status:** gaps_found
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `docker compose build cms` from clean state produces image with all 15 routes responding — no docker cp required | PARTIAL | Image 44cf772ff9b2 built from TS source confirming routes are baked in; but fails to start due to Node.js 20.20.1 ESM regression. Fix applied (Dockerfile pinned to 20.20.0), corrected rebuild not yet run. |
| 2 | Freshly started CMS container returns expected HTTP status on all 15 routes without post-start injection | FAILED | Running container (19101238eeb3) is old pre-TS image. Smoke rows in TEST_REPORT.md marked BLOCKED. No confirmed post-rebuild route verification. |
| 3 | admin-dashboard and kiosk-app Dockerfiles reference node:20-alpine; rebuilt images pass login and product-display checks | PARTIAL | Static Dockerfile check: PASS (both use node:20-alpine AS build). INFRA-03 functional check (smoke-post-rebuild.sh): DEFERRED — blocked on CMS rebuild. |
| 4 | CMS Dockerfile references node:20-alpine; CMS health endpoint returns 204 after rebuild | PARTIAL | CMS Dockerfile uses node:20.20.0-alpine (valid supported LTS 20 pin — satisfies intent). CMS health 204 cannot be confirmed for new image because new image fails to start. |

**Score: 1/4 success criteria fully verified** (CMS-01 offline TS source check passes; CMS-02/CMS-03/INFRA-03 blocked on VPS rebuild)

---

### Required Artifacts

#### Plan 01-01 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `project/scripts/smoke-cms-routes.sh` | Curl-based route verification for all 15 Strapi routes | VERIFIED | 119 lines, LF endings, passes bash -n, covers 13 collectionType + 2 singleType via check_route, plus 2 custom handler routes. Uses `Authorization: Bearer` JWT auth. Exits 1 on failure. |
| `project/scripts/smoke-post-rebuild.sh` | Post-rebuild verification (health, login, kiosk, admin) | VERIFIED | 125 lines, LF endings, passes bash -n, covers 4 checks (CMS health 204, CMS login JWT, kiosk products data, admin login JWT). Exits 1 on failure. |
| `project/PATCHLOG.md` | Phase 1 v3.4.6 entry with what/why/risk/rollback | VERIFIED | v3.4.6 entry present (grep count: 1). Contains What/Why/Risk/Rollback sections. Commits: b6ec297. |
| `project/TEST_REPORT.md` | Phase 1 section stub | VERIFIED (partial) | Phase 1 section present with filled-in static check rows (PASS). Smoke rows marked BLOCKED (not PENDING — more accurate). No PENDING rows remain. Phase 1 Summary section present. |

#### Plan 01-02 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `project/TEST_REPORT.md` | Phase 1 smoke results filled in (PASS/FAIL) | STUB | Smoke rows are BLOCKED, not filled with actual pass/fail results. Plan 01-02 is incomplete — all tasks were human-checkpoint tasks that required VPS access; the Node.js regression prevented completion. |

#### Plan 01-03 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `project/admin-dashboard/Dockerfile` | node:20-alpine base image | VERIFIED | Line 1: `FROM node:20-alpine AS build`. Satisfies INFRA-01. |
| `project/kiosk-app/Dockerfile` | node:20-alpine base image | VERIFIED | Line 1: `FROM node:20-alpine AS build`. Satisfies INFRA-01. |
| `project/inventory-cms/Dockerfile` | node:20-alpine base image (both stages) | VERIFIED (with note) | Both stages use `node:20.20.0-alpine` (not `node:20-alpine`). This is a valid Node.js 20 LTS pin and is intentionally stricter than generic `node:20-alpine` — applied to fix the 20.20.1 ESM regression. Satisfies INFRA-02 intent. |
| `project/TEST_REPORT.md` | Static check rows PASS | VERIFIED | Static check rows show PASS for all three Dockerfiles. Commit 2cec0a2 + 5e747b0 (node:20.20.0-alpine pin) exist. |

---

### CMS-01 Deep Verification: TypeScript Source Coverage

The core of CMS-01 is that all 15 API routes exist in TypeScript source and survive rebuild. This is verifiable entirely offline.

**All 15 required API directories present in `project/inventory-cms/src/api/`:**

| API (URL plural) | Src Directory | Routes File | TS Files | Status |
|-----------------|---------------|-------------|----------|--------|
| products | `product/` | `product.ts` | 3 | VERIFIED |
| orders | `order/` | `order.ts` | 4 | VERIFIED |
| customers | `customer/` | `customer.ts` | 3 | VERIFIED |
| ingredients | `ingredient/` | `ingredient.ts` | 3 | VERIFIED |
| payments | `payment/` | `payment.ts` | 4 | VERIFIED |
| delivery-assignments | `delivery-assignment/` | `delivery-assignment.ts` | 3 | VERIFIED |
| funnel-events | `funnel-event/` | `funnel-event.ts` | 3 | VERIFIED |
| inbound-messages | `inbound-message/` | `inbound-message.ts` | 3 | VERIFIED |
| feedbacks | `feedback/` | `feedback.ts` | 3 | VERIFIED |
| suppliers | `supplier/` | `supplier.ts` | 3 | VERIFIED |
| loyalty-tiers | `loyalty-tier/` | `loyalty-tier.ts` | 3 | VERIFIED |
| marketing-campaigns | `marketing-campaign/` | `marketing-campaign.ts` | 3 | VERIFIED |
| delivery-zones | `delivery-zone/` | `delivery-zone.ts` | 3 | VERIFIED |
| system-config (singleType) | `system-config/` | `system-config.ts` | 5 | VERIFIED |
| restaurant-brand (singleType) | `restaurant-brand/` | `restaurant-brand.ts` | 3 | VERIFIED |

**All 15 route files use `factories.createCoreRouter` — substantive implementation, not stubs.**

CMS-01 is satisfied at the source level. The remaining CMS-02/CMS-03 gap is VPS execution, not source completeness.

---

### Key Link Verification

#### Plan 01-01 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `smoke-cms-routes.sh` | `http://127.0.0.1:1337/api/*` | curl with Bearer token auth | WIRED | Pattern `Authorization.*Bearer` found 3 times in script. check_route() function uses `Authorization: Bearer ${TOKEN}` on every route check. |
| `smoke-post-rebuild.sh` | `http://127.0.0.1:1337/_health` | curl, expects HTTP 204 | WIRED | Pattern `_health` found once. Script checks `HEALTH_STATUS = "204"` and prints PASS/FAIL accordingly. |

#### Plan 01-02 Key Links (VPS-only — cannot verify offline)

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| VPS docker-compose | cms container | docker compose build --no-cache | NOT_VERIFIED | Requires VPS execution. Build ran once (produced 44cf772ff9b2) but image fails to start. Corrected rebuild not yet run. |
| gateway container | cms container | nginx -s reload | NOT_VERIFIED | Cannot verify offline. Only verifiable on VPS after CMS rebuild. |

#### Plan 01-03 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `admin-dashboard/Dockerfile` | `node:20-alpine` | FROM instruction line 1 | WIRED | `FROM node:20-alpine AS build` — exact match. |
| `kiosk-app/Dockerfile` | `node:20-alpine` | FROM instruction line 1 | WIRED | `FROM node:20-alpine AS build` — exact match. |
| `inventory-cms/Dockerfile` | `node:20-alpine` | FROM instruction lines 4 and 33 | WIRED (with deviation) | Uses `node:20.20.0-alpine` instead of `node:20-alpine` — intentional precision pin, not a regression. Both stages pinned. |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| CMS-01 | 01-01, 01-02 | All 15 API routes defined in TS source and survive rebuild | SATISFIED | All 15 directories verified in `src/api/` with `factories.createCoreRouter` TS files. Routes baked into image 44cf772ff9b2 (confirmed by build log — no docker cp used). |
| CMS-02 | 01-01, 01-02 | CMS Docker image rebuilt without losing any API routes | PARTIAL | Clean rebuild completed (44cf772ff9b2). Routes are in source. BUT image cannot start due to Node.js 20.20.1 bug. Fix pinned (node:20.20.0-alpine). Second rebuild required to fully satisfy. |
| CMS-03 | 01-01, 01-02 | All Strapi API routes return correct HTTP status after fresh container start | BLOCKED | Cannot verify — no working freshly-started image yet. Blocked on CMS-02 completion. |
| INFRA-01 | 01-01, 01-03 | admin-dashboard and kiosk-app Dockerfiles use node:20-alpine | SATISFIED | Both Dockerfiles verified: `FROM node:20-alpine AS build` on line 1. Static check confirmed, PASS recorded in TEST_REPORT.md. |
| INFRA-02 | 01-03 | CMS Dockerfile uses node:20-alpine | SATISFIED (with note) | CMS Dockerfile uses `node:20.20.0-alpine` — a precise LTS 20 pin. Satisfies INFRA-02 intent (upgrade from EOL node:18). The deviation is additive (stricter pin = better supply-chain). |
| INFRA-03 | 01-01, 01-03 | Rebuilt images verified to function correctly (login, product display, CMS health) | DEFERRED | smoke-post-rebuild.sh script exists and is syntactically valid. Functional execution deferred — CMS rebuild must complete first. |

**Orphaned requirements check:** REQUIREMENTS.md maps CMS-01, CMS-02, CMS-03, INFRA-01, INFRA-02, INFRA-03 to Phase 1. All six are claimed in plan frontmatter. No orphaned requirements.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `project/TEST_REPORT.md` | 18-19 | `BLOCKED` rows in Phase 1 smoke section | Warning | Not a code defect — accurately documents that smoke could not run. Does mean CMS-02/CMS-03 evidence is absent. |

No stub implementations, hardcoded credentials, TODO/FIXME comments, or empty handlers found in any phase-1 artifact.

**Node.js version discrepancy:** Plan 01-03 expected `node:20-alpine` in CMS Dockerfile; actual is `node:20.20.0-alpine`. This is intentional — applied during Plan 01-02 to resolve a Node.js 20.20.1 ESM regression. The deviation is documented in both 01-02 SUMMARY and 01-03 SUMMARY. No impact on INFRA-02 compliance (the requirement is satisfied by either form).

---

### Human Verification Required

#### 1. CMS Rebuild with Pinned Node.js

**Test:** SSH to VPS, confirm at least 10GB free disk, run `docker compose build cms --no-cache` from `/opt/resto/current/`, then `docker compose up -d cms`, wait for `/_health` to return 204.

**Expected:** Build completes without error; `docker logs current-cms-1` shows Strapi startup; `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:1337/_health` returns 204.

**Why human:** Requires SSH to VPS at 72.60.190.192; build takes 15-30 minutes on 2-CPU VPS; cannot be verified programmatically from this machine.

#### 2. CMS Route Smoke Test

**Test:** After rebuild, run `STRAPI_EMAIL=adel.zeriri@gmail.com STRAPI_PASSWORD=RestoBot2026 bash project/scripts/smoke-cms-routes.sh http://127.0.0.1:1337`

**Expected:** All 15 route lines show `PASS`; final output `Results: 15/15 passed` (or 17/17 including custom handlers); exit code 0.

**Why human:** Requires live CMS container on VPS with JWT auth working; network-dependent.

#### 3. Post-Rebuild Smoke (INFRA-03)

**Test:** Run `STRAPI_EMAIL=adel.zeriri@gmail.com STRAPI_PASSWORD=RestoBot2026 bash project/scripts/smoke-post-rebuild.sh`

**Expected:**
```
PASS  CMS health (204)
PASS  CMS login (JWT obtained)
PASS  kiosk products via gateway (200, data present)
PASS  admin login via gateway (200, JWT)
Results: 4/4 passed
```

**Why human:** Requires live VPS stack with rebuilt CMS + nginx DNS flush; verifies end-to-end gateway routing, not just CMS in isolation.

---

### Gaps Summary

Phase 1 has two root causes generating three downstream gaps:

**Root cause: VPS rebuild incomplete.** The Node.js 20.20.1 ESM regression was diagnosed and a correct fix (pinning `node:20.20.0-alpine`) was committed (commit `2cec0a2`). However the *corrected* `docker compose build cms --no-cache` has not yet run. Until it does:

1. **CMS-02 is partial** — a rebuild ran but the resulting image cannot start. The phase goal "CMS build is self-contained" requires a *working* container, not just a build artifact.

2. **CMS-03 is blocked** — cannot test route responses from a non-starting container. The smoke scripts exist and are correct; they simply have no valid target yet.

3. **INFRA-03 is deferred** — `smoke-post-rebuild.sh` depends on a healthy CMS container to test CMS health and login. The admin-dashboard and kiosk-app static checks are fine; the functional end-to-end check cannot run.

**What has been achieved (offline-verifiable):**

- All 15 Strapi API routes exist as full MVC TypeScript source in `project/inventory-cms/src/api/` (CMS-01: satisfied).
- Both smoke scripts are complete, syntactically valid, LF line endings, and cover the full route matrix.
- PATCHLOG v3.4.6 and TEST_REPORT Phase 1 section are present with accurate documentation.
- INFRA-01 and INFRA-02 are satisfied (all three service Dockerfiles use Node.js 20 LTS).
- The Dockerfile fix that unblocks the rebuild is already committed.

**One VPS session** (run rebuild, run smoke scripts, update TEST_REPORT.md) closes all three gaps simultaneously.

---

_Verified: 2026-03-19_
_Verifier: Claude (gsd-verifier)_
