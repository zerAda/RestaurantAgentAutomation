# Remaining Work — v1.0 Platform Hardening (Phases 11–14)

**Created:** 2026-06-19
**Source of truth:** `.planning/v1.0-MILESTONE-AUDIT.md` (audited 2026-04-04, `status: gaps_found`)
**Status at last reconciliation:** 27/34 requirements satisfied; 10/14 phases complete.

This is the consolidated, deploy-aware checklist for the four remaining phases. Each item is tagged:

- 🟢 **LOCAL** — code/doc change made in this repo, verifiable in CI; safe from any environment
- 🔴 **VPS** — requires SSH to the production VPS (`deploy@72.60.190.192`); **DEFERRED** until a prod-connected session

The 7 unsatisfied requirements are: **METR-01, METR-02, METR-04, METR-05** (Phase 12), **AUDIT-02, AUDIT-04** (Phase 11), **AUDIT-03** (Phases 11+13).

---

## Phase 11 — VPS Ops: Apply DB Migration & Activate Audit Chain  🔴 VPS-ONLY (DEFERRED)

Unblocks **AUDIT-02, AUDIT-04** (and AUDIT-03 alongside Phase 13). Researched in `11-RESEARCH.md`; no plan written.
**Critical:** the `ops.workflow_audit` table lives in the **n8n** database (user=`n8n`, db=`n8n`), NOT strapi. The audit report's `psql -U strapi -d strapi` line is an error — do not use it.

- [ ] 🔴 Apply Phase-3 migration into the n8n DB:
      `docker compose exec -T postgres psql -U n8n -d n8n < db/migrations/2026-03-23_p3_workflow_audit.sql`
      Verify: `SELECT to_regclass('ops.workflow_audit');` returns non-null.
- [ ] 🔴 Recreate the gateway container to pick up the committed `/v1/internal/` nginx route:
      `docker compose up -d gateway` — then `curl -sf https://api.${DOMAIN_NAME}/v1/internal/health` (or equivalent) returns 2xx.
- [ ] 🔴 Re-import `W_AUDIT_ARCHIVE.json` (n8n 2.x-compatible cron, commit 8bd4c33) via the n8n API, then activate:
      `UPDATE workflow_entity SET active = true WHERE name = 'W_AUDIT_ARCHIVE';` and restart n8n.
- [ ] 🔴 Verify AUDIT-02: trigger an inbound adapter, confirm a row appears in `ops.workflow_audit`.
- [ ] 🟢 (optional) Write `11-01-PLAN.md` documenting the above as a repeatable runbook before executing.

---

## Phase 12 — W_QUEUE_METRICS Runtime Fix  🟢 LOCAL code + 🔴 VPS import

Unblocks **METR-01, METR-02, METR-04, METR-05**. Empty directory — needs planning + execution.
Root causes (audit INT-02, WARN-04): credential IDs are empty `$env.*` expressions; the disk check regressed to GNU `stat -f -c` which busybox/Alpine rejects.

- [ ] 🟢 In `W_QUEUE_METRICS.json`, replace the PG credential `id: "={{$env.N8N_DB_CREDENTIAL_ID || ''}}"` with the hardcoded `"id": "1mZZJEscADgQ8InR"` (matches the other audit workflows). Do the same for the Redis credential (`$env.REDIS_CREDENTIAL_ID`).
- [ ] 🟢 Restore the disk check to `df -k /` (the Phase-07 fix) in place of `stat -f -c '%a %s %b' /`. This makes `diskUsedPct` compute correctly so the `>= 80` guard (METR-05) can fire.
- [ ] 🟢 Add a workflow-JSON lint/assertion to the integrity gate so credential IDs can't regress to empty `$env` expressions again (prevents recurrence).
- [ ] 🔴 Import the updated `W_QUEUE_METRICS.json` on VPS; confirm the PG node reads queue depth and the disk node emits a value ≥ 0.
- [ ] 🔴 Verify METR-04/05 alerts: force queue depth > 50 (or lower the threshold in a test) and disk > 80% to confirm CRITICAL alerts emit.

---

## Phase 13 — Admin Dashboard Audit-Log Repair  🟢 LOCAL code + 🔴 VPS rebuild

Unblocks **AUDIT-03**. Empty directory — needs planning + execution. Depends on Phase 11 (ops table).
Root cause (audit INT-03 + WARN-01/02/03): `VITE_API_URL` is declared as an `ARG` but not passed by compose (URL resolves to the unrouted `/api/webhook/...`); plus three W_AUDIT_QUERY defects.

- [ ] 🟢 Add `VITE_API_URL: https://api.${DOMAIN_NAME}` to the `admin-dashboard` build args in `docker-compose.hostinger.prod.yml` (and any other compose file that builds the dashboard).
- [ ] 🟢 W_AUDIT_QUERY: add the second PG node that executes `countQuery` so `total` is the global count, not the page length.
- [ ] 🟢 W_AUDIT_QUERY: reconcile `limit` vs `page_size` (AuditLogView sends `limit`; workflow reads `page_size`) — pick one and align both ends.
- [ ] 🟢 W_AUDIT_QUERY: add WHERE clauses for the `status` and `channel` filters the UI already sends.
- [ ] 🔴 Rebuild and deploy the admin-dashboard image on VPS; confirm AuditLogView fetches `https://api.${DOMAIN_NAME}/v1/internal/audit-log` and renders rows with correct pagination/filtering.

---

## Phase 14 — Nyquist Compliance & Documentation Cleanup  🟢 LOCAL (no VPS)

Process/quality. Empty directory. Safe to do entirely in this repo — no prod access needed.
Best done **after** 11–13 so verification reflects real runtime state, but the doc-debt items below can proceed now.

- [ ] 🟢 Create `09-VERIFICATION.md` (Phase 09): document CI goals as verified and the 3 VPS blockers as deferred to Phase 11.
- [ ] 🟢 Create `03-VALIDATION.md` (Phase 03 — currently MISSING).
- [ ] 🟢 Lift `01`, `07`, `09`, `10` VALIDATION.md from draft (`nyquist_compliant: false`) to compliant.
- [ ] 🟢 (DONE 2026-06-19) Close stale ROADMAP.md / REQUIREMENTS.md checkboxes — reconciled in this pass.
- [ ] 🟢 Address documented tech debt where cheap: `admin-dashboard/Dockerfile` line ~28 missing `RUN` before touch/chown (WARN-06); `W1_IN_WA.json "active": false` deployment trap (WARN-05).

---

## Recommended execution order (when resuming)

1. **Phase 14 doc items** (🟢, no VPS) — clears the verification/validation debt immediately.
2. **Phase 12 + 13 local code** (🟢) — land the workflow/compose/dashboard fixes in a PR; CI validates structure.
3. **Phase 11 + the 🔴 deploy/import/verify steps of 12 & 13** — in a single prod-connected session with VPS SSH.

Once all 🔴 items are verified on VPS, re-run `/gsd:audit-milestone` to confirm 34/34, then `/gsd:complete-milestone v1.0`.

---

## Progress update — 2026-06-20 (branch `claude/gap-closure-phases-12-14`)

The **local (🟢) work for Phases 12, 13, and 14 is COMPLETE**. What remains is purely 🔴 VPS deployment.

| Phase | Local 🟢 | VPS 🔴 |
|-------|----------|--------|
| 12 — W_QUEUE_METRICS | ✅ DONE — credential IDs hardcoded (PG `1mZZJEscADgQ8InR`, Redis `43SDqJYMGa6RvFqW`); disk check switched to `df -k /` | ⏳ import workflow on VPS; verify METR-04/05 alerts fire |
| 13 — Admin audit-log | ✅ DONE — `VITE_API_URL` build arg (prod+base); AuditLogView dead var removed; W_AUDIT_QUERY count node + `limit` alias + status/channel filters | ⏳ rebuild+deploy admin-dashboard; e2e verify (needs Phase 11 ops table) |
| 14 — Nyquist/docs | ✅ DONE — 09-VERIFICATION.md (partial) + 03-VALIDATION.md created; 01/07/09/10 VALIDATIONs lifted to compliant | n/a (no VPS) |
| 11 — VPS ops | n/a | ⏳ apply migration; recreate gateway; activate W_AUDIT_ARCHIVE |

**Still TODO (not done in the 2026-06-20 pass):**
- 🔴 All VPS deploy/import/verify steps above (Phase 11 + the deploy rows of 12/13).
- 🟢 (optional hardening, deferred) integrity-gate lint to block empty `$env` credential IDs (Phase 12 item 3); `admin-dashboard/Dockerfile` missing-`RUN` and `W1_IN_WA.json active:false` tech-debt items (Phase 14 item 5).

When the 🔴 items are verified on VPS: re-run `/gsd:audit-milestone` (expect 34/34) → `/gsd:complete-milestone v1.0`.
