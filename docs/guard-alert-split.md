# Guard Alert Split: `GUARD_ERROR_FAILCLOSED` vs `NO_ENTITLEMENT`

**Status:** Accepted (downstream classifier shipped; live wiring 🔴 VPS-deferred)
**Date:** 2026-06-20
**Phase:** 20
**Requirement:** GRD-01 (criterion 4)

---

## Context

`W0_MODULE_GUARD` already emits **distinct, stable reason prefixes** for every deny:

- `GUARD_ERROR_FAILCLOSED: …` — the guard **could not determine** entitlement (Strapi
  unreachable / 401 from a missing-or-expired `STRAPI_API_TOKEN_INTERNAL` / invalid body).
  This is an **infrastructure outage**: with the guard failing closed, it denies **every**
  inbound message and operator action.
- `NO_ENTITLEMENT: …` / `MODULE_NOT_FOUND: …` / `EXPIRED: …` — **legitimate denials**: the
  tenant simply lacks (or lost) the module. Normal business outcomes.
- `GUARD_ERROR: … not provided` — a **caller bug** (missing `tenant_id`/`module_key`).

But today every deny is logged **identically**. The caller deny branch
`W1_IN_WA.json` → `B0 - Log Deny (DB)` writes a **hardcoded `'HIGH'`** severity into
`security_events` (`W1_IN_WA.json:240`), and the alert plane `W8_OPS.json`
(`E1 - On Error` errorTrigger → `E2 - Normalize Error` → `E3 - Save Error (DB)` →
`E4 - Optional Alert Webhook` posting to `$env.ALERT_WEBHOOK_URL`, `W8_OPS.json:78-129`)
has no notion of the deny reason. So a **missing-token total outage**
(`GUARD_ERROR_FAILCLOSED`) is indistinguishable from a tenant lacking a module
(`NO_ENTITLEMENT`) — the outage does not page.

## The severity contract

The single source of truth is the pure seam **`scripts/guard/classify-deny.mjs`**
`classify(reason)`:

| Reason prefix                                    | `class`            | `severity` | `pageable` | `alertKey`         |
| ------------------------------------------------ | ------------------ | ---------- | ---------- | ------------------ |
| `GUARD_ERROR_FAILCLOSED*`                        | `cannot-determine` | **HIGH**   | **true**   | `GUARD_FAILCLOSED` |
| `NO_ENTITLEMENT*` / `MODULE_NOT_FOUND*` / `EXPIRED*` | `denial`        | `LOW`      | `false`    | `null`             |
| `GUARD_ERROR:` (input / caller error)            | `caller-bug`       | `MEDIUM`   | `false`    | `null`             |
| `ENTITLED_CACHED` / `GLOBAL_ENABLED_CACHED` / `ENTITLED` / `GLOBAL_ENABLED` | `allow` | `LOW` | `false` | `null` |
| **anything else / `''` / `null`**                | `unknown`          | **HIGH**   | **true**   | `GUARD_UNKNOWN`    |

`GUARD_ERROR_FAILCLOSED` is matched **before** the generic `GUARD_ERROR:` prefix so the
pageable outage case is never shadowed by the non-paged caller-bug case. The **unknown**
branch defaults to **pageable HIGH** so a brand-new failure mode is surfaced, not silently
swallowed.

## Downstream wiring (no guard-topology edit — O-3)

`classify()` plugs into the **existing** alert plane WITHOUT editing
`workflows/W0_MODULE_GUARD.json`. The guard (20-01) is unchanged — it just keeps emitting
the stable prefixes; the classification lives downstream (clean disjoint ownership):

1. **`security_events.severity`** — the caller deny branch (e.g. `W1_IN_WA`'s
   `B0 - Log Deny (DB)`) writes `severity` from **`classify(reason).severity`** instead of
   the hardcoded `'HIGH'` at `W1_IN_WA.json:240`. So a `NO_ENTITLEMENT` deny is logged `LOW`
   and a `GUARD_ERROR_FAILCLOSED` deny is logged `HIGH`.
2. **`ALERT_WEBHOOK_URL` page** — an `IF` on **`classify(reason).pageable`** fans the
   FAILCLOSED (and any unknown) case to the `W8_OPS` `E4 - Optional Alert Webhook` POST
   (`$env.ALERT_WEBHOOK_URL`), tagged with `alert_key = classify(reason).alertKey`
   (`GUARD_FAILCLOSED` / `GUARD_UNKNOWN`). Legitimate `NO_ENTITLEMENT` / `EXPIRED` /
   `MODULE_NOT_FOUND` denials are `pageable:false` → logged only, **no page**.

This reuses the shipped alerting plane (`security_events` severity column + the `W8_OPS`
`ALERT_WEBHOOK_URL` path); no new alert system, no guard-topology edit.

## 🔴 VPS Deferrals

The actual edit to the caller deny-branch (`security_events.severity` from `classify()`)
and the `W8_OPS` `pageable` fan-out, plus importing the updated workflows on the prod n8n,
is a **prod-connected session** step (the workflow import is already a Phase-20 🔴 VPS
deferral). This document records the contract + the wiring; the live edit executes there.

## Contract stability

The reason prefixes — `GUARD_ERROR_FAILCLOSED`, `NO_ENTITLEMENT`, `MODULE_NOT_FOUND`,
`EXPIRED` — MUST stay byte-stable between the guard (`workflows/W0_MODULE_GUARD.json` /
`scripts/guard/entitlement-decision.mjs`, 20-01) and the classifier
(`scripts/guard/classify-deny.mjs`, 20-03). The CI job `guard-alert-classifier` in
`.github/workflows/phase-20-assertions.yml` greps the guard JSON for `GUARD_ERROR_FAILCLOSED`
and `NO_ENTITLEMENT` to keep them in sync (a READ-ONLY check — 20-03 never writes the guard).
