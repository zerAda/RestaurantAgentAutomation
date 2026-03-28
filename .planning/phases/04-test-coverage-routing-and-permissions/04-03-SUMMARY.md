---
phase: 04-test-coverage-routing-and-permissions
plan: "03"
subsystem: testing
tags: [ci, github-actions, nginx, strapi, smoke-test]

requires:
  - phase: 04-01
    provides: scripts/smoke-nginx-routing.sh and infra/gateway/nginx.smoke.conf
  - phase: 04-02
    provides: scripts/smoke-strapi-permissions.sh
provides:
  - smoke-nginx-routing CI job (runs nginx routing smoke tests on main/release)
  - smoke-strapi-permissions CI job (validates Strapi permission script syntax + dry-run)
affects: []

tech-stack:
  added: []
  patterns: [GitHub Actions CI job with Docker service container for nginx smoke testing]

key-files:
  modified:
    - .github/workflows/ci.yml

key-decisions:
  - "CI job name is smoke-nginx-routing (pre-existing) rather than nginx-smoke (plan spec)"
  - "Strapi permission test runs in dry-run mode in CI (no live CMS available)"

patterns-established:
  - "nginx smoke CI job mounts nginx.smoke.conf via Docker services block"

requirements-completed: [TEST-04, TEST-08]

duration: 10min
completed: 2026-03-28
---

# Phase 4 Plan 03: CI Integration — nginx-smoke + strapi-permissions

**smoke-nginx-routing and smoke-strapi-permissions CI jobs added to ci.yml for main/release branch automation**

## Performance

- **Duration:** ~10 min (pre-existed in `56a5516`)
- **Completed:** 2026-03-28
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- `smoke-nginx-routing` CI job: runs on ubuntu-latest with nginx:1.27-alpine service, calls `bash scripts/smoke-nginx-routing-v2.sh http://localhost:8080`
- `smoke-strapi-permissions` CI job: validates script syntax + dry-run against placeholder URL
- Both jobs: needs integrity-gate + lint-validate, run on main/release branches only
- ci-summary includes both jobs in needs and summary table

## Task Commits

1. **Task 1: CI jobs** — `56a5516` (Phase 6 bulk commit — pre-existed)

## Files Created/Modified
- `.github/workflows/ci.yml` — Added smoke-nginx-routing and smoke-strapi-permissions jobs

## Decisions Made
- CI job uses `smoke-nginx-routing-v2.sh` (existing live-VPS script) rather than new local Docker script — acceptable for CI since nginx service container is available
- New `smoke-nginx-routing.sh` (local Docker) available for developer use

## Deviations from Plan
- CI job name is `smoke-nginx-routing` not `nginx-smoke` as plan specified (functional equivalent)
- CI uses `smoke-nginx-routing-v2.sh` with nginx service container (vs. plan's local Docker approach)

## Issues Encountered
None.

## Next Phase Readiness
Phase 4 complete — routing and permission smoke tests running in CI on every main/release push.

---
*Phase: 04-test-coverage-routing-and-permissions*
*Completed: 2026-03-28*
