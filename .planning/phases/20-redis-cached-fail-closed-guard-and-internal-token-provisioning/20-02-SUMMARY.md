---
phase: 20-redis-cached-fail-closed-guard-and-internal-token-provisioning
plan: 02
subsystem: infra
tags: [secrets, docker-compose, env, preflight, strapi, ent-03, ci]

# Dependency graph
requires:
  - phase: 20-redis-cached-fail-closed-guard-and-internal-token-provisioning
    provides: "20-01 created phase-20-assertions.yml (this plan appends the ENT-03 job); the guard reads STRAPI_API_URL + STRAPI_API_TOKEN_INTERNAL + the TTL envs declared here"
provides:
  - "STRAPI_API_TOKEN_INTERNAL as a first-class secret: HARD ${VAR:?} in prod compose (both n8n services), SOFT ${VAR:-} in base compose, in .env.example, annotated in the secrets inventory"
  - "STRAPI_API_URL + ENTITLEMENT_CACHE_TTL_SEC=300 / ENTITLEMENT_NEG_CACHE_TTL_SEC=60 in both composes + .env.example"
  - "scripts/preflight.sh fail-fast (REQ_VARS) + scripts/preflight-prod.sh STRAPI_KEYS placeholder rejection"
  - "ent03-token-wiring CI job appended to phase-20-assertions.yml"
affects: [20-03, guard, secrets, deployment, vps-provisioning]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "compose ${VAR:?msg} hard-fail (prod) + ${VAR:-} soft (base/dev) + preflight REQ_VARS double fail-fast for a required secret"

key-files:
  created: []
  modified:
    - docker-compose.hostinger.prod.yml
    - docker-compose.base.yml
    - config/.env.example
    - docs/SECRETS_ROTATION_REQUIRED.md
    - scripts/preflight.sh
    - scripts/preflight-prod.sh
    - .github/workflows/phase-20-assertions.yml

key-decisions:
  - "Hard ${VAR:?} on prod (both n8n-main + n8n-worker), soft ${VAR:-} on base, preflight as the CI-testable docker-free gate (O-2) — prod refuses to start tokenless while dev/CI compose config stays green"
  - "Extended scripts/preflight-prod.sh STRAPI_KEYS too (O-5) so the prod .env validator rejects an unprovisioned/tobemodified token, not only the general preflight.sh"

patterns-established:
  - "Required-secret double fail-fast: compose hard-fail + preflight REQ_VARS"

requirements-completed: [ENT-03]

# Metrics
duration: 3min
completed: 2026-06-20
---

# Phase 20 Plan 02: Internal Token Provisioning Summary

**`STRAPI_API_TOKEN_INTERNAL` made a first-class secret — HARD `${VAR:?}` in prod compose (both n8n services), SOFT in base, declared in `.env.example` + the secrets inventory, with `scripts/preflight.sh` failing fast (`❌ Missing env: STRAPI_API_TOKEN_INTERNAL`, exit 1) so the fail-closed guard can never turn an unprovisioned secret into a silent total lockout.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-06-20T18:40:34Z
- **Completed:** 2026-06-20T18:43:46Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments
- `STRAPI_API_TOKEN_INTERNAL` declared HARD `${VAR:?…}` in BOTH n8n-main and n8n-worker of `docker-compose.hostinger.prod.yml`; SOFT `${VAR:-}` in BOTH n8n services of `docker-compose.base.yml` — plus `STRAPI_API_URL` + `ENTITLEMENT_CACHE_TTL_SEC=300` / `ENTITLEMENT_NEG_CACHE_TTL_SEC=60` in all four blocks.
- `config/.env.example` gains the token (`tobemodified  # [SECRET]`, gitleaks-allowlisted) + URL + the two TTL envs; `docs/SECRETS_ROTATION_REQUIRED.md` annotates the (already-listed) token as the W0_MODULE_GUARD internal token whose absence = total lockout.
- `scripts/preflight.sh` REQ_VARS extended — the negative test (`env -u STRAPI_API_TOKEN_INTERNAL bash scripts/preflight.sh`) exits 1 with `❌ Missing env: STRAPI_API_TOKEN_INTERNAL`. `scripts/preflight-prod.sh` STRAPI_KEYS extended (O-5) to reject a placeholder token in the prod `.env`.
- `ent03-token-wiring` CI job appended to `phase-20-assertions.yml` asserting prod-HARD vs base-NOT-hard + the negative preflight test; 20-01 jobs intact.

## Task Commits

1. **Task 1: Compose env wiring (hard prod / soft base)** - `61c5354` (feat)
2. **Task 2: .env.example + secrets inventory + preflight fail-fast** - `e29e130` (feat)
3. **Task 3: Append ent03-token-wiring CI job** - `36bc3d2` (feat)

## Files Created/Modified
- `docker-compose.hostinger.prod.yml` - HARD token + soft URL + TTLs in n8n-main & n8n-worker
- `docker-compose.base.yml` - SOFT token + URL + TTLs in n8n-main & n8n-worker
- `config/.env.example` - token (tobemodified/[SECRET]) + URL + TTL envs
- `docs/SECRETS_ROTATION_REQUIRED.md` - annotation of the guard token / lockout risk
- `scripts/preflight.sh` - token + URL in REQ_VARS (fail-fast)
- `scripts/preflight-prod.sh` - token added to STRAPI_KEYS placeholder check (O-5)
- `.github/workflows/phase-20-assertions.yml` - appended ent03-token-wiring job + extended paths

## Decisions Made
- O-2: hard prod / soft base + preflight gate — prevents Pitfall-6 lockout while keeping CI/dev compose-config green.
- O-5: `preflight-prod.sh` had an analogous `STRAPI_KEYS` slot, so the token was added there too (rejects `tobemodified`/empty in the prod `.env`); `preflight.sh` remains the CI-tested negative-test gate.

## Deviations from Plan

None - plan executed exactly as written. `preflight-prod.sh` had a clean analogous slot (STRAPI_KEYS), so the token was added there per the O-5 instruction rather than only noted.

## Issues Encountered
None.

## User Setup Required
🔴 VPS-deferred (tracked, not attempted): provisioning the REAL `STRAPI_API_TOKEN_INTERNAL` value (a Strapi-admin-generated internal API token) into the prod env, and confirming `STRAPI_API_URL` points at the in-network Strapi (`http://strapi:1337`). The hard `${VAR:?}` on prod guarantees prod n8n won't start until the value exists.

## Next Phase Readiness
- The guard's token + URL + TTL envs are now wired; 20-03 (alert classifier) appends its job to the same CI gate.

## Self-Check: PASSED

- FOUND: docker-compose.hostinger.prod.yml, docker-compose.base.yml, config/.env.example, docs/SECRETS_ROTATION_REQUIRED.md, scripts/preflight.sh, scripts/preflight-prod.sh, .github/workflows/phase-20-assertions.yml
- FOUND commits: 61c5354, e29e130, 36bc3d2

---
*Phase: 20-redis-cached-fail-closed-guard-and-internal-token-provisioning*
*Completed: 2026-06-20*
