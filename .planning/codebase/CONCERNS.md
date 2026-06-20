# Codebase Concerns

**Analysis Date:** 2026-06-20
**Platform:** RESTO BOT — multi-channel restaurant ordering automation (Strapi 5 CMS + n8n 2.9.4 + Postgres/Redis on a single 119 GB Hostinger VPS)
**Primary sources:** `.planning/v1.0-MILESTONE-AUDIT.md` (2026-04-04), `SRE_AUDIT_REPORT.md` (2026-03-23 / updated 2026-04-06), `SECRETS_INVENTORY.md`, `SECRETS_ACTION_PLAN.md`, `.gitleaks.toml`, `.github/workflows/security-scan.yml` + `secret-scan.yml`, and the `workflows/` set (100 JSON files).

> Severity legend: **P0** = production-breaking or active data/security exposure · **P1** = high-impact, degrades a shipped feature · **P2** = tech debt / latent risk.

---

## Tech Debt

**W_QUEUE_METRICS credential IDs are empty env-var expressions (P0 — runtime broken)**
- Issue: `workflows/W_QUEUE_METRICS.json` PG node (line 41) uses `"id": "={{$env.N8N_DB_CREDENTIAL_ID || ''}}"` and the Redis nodes (lines 69, 100) use `"id": "={{$env.REDIS_CREDENTIAL_ID || ''}}"`. Neither `N8N_DB_CREDENTIAL_ID` nor `REDIS_CREDENTIAL_ID` is defined in `docker-compose.hostinger.prod.yml` or `.env.example`, so both expressions evaluate to `''` at runtime and the credential is not found.
- Why: Other audit workflows hardcode the working credential `1mZZJEscADgQ8InR`; W_QUEUE_METRICS was parameterized against env vars that were never wired into compose (regression introduced during Phase 09 credential patching).
- Impact: PG and Redis nodes fail silently on every 5-minute run. Queue depth, error rate, and queue-depth alerting never emit. Breaks **METR-01, METR-02, METR-04** (per `.planning/v1.0-MILESTONE-AUDIT.md` INT-02 / FLOW-01, severity critical).
- Fix approach: Replace both expression-based IDs with the literal `"1mZZJEscADgQ8InR"` (PG) and `"43SDqJYMGa6RvFqW"` (Redis, per `SECRETS_ACTION_PLAN.md`), OR add `N8N_DB_CREDENTIAL_ID` / `REDIS_CREDENTIAL_ID` to the n8n-main and n8n-worker env blocks in compose. Re-import the workflow on the VPS.
- Status: **Confirmed still present** in the current `workflows/W_QUEUE_METRICS.json` (lines 41, 69, 100).

**Phase 3 audit migration never applied to VPS (P0 — runtime broken)**
- Issue: `db/migrations/2026-03-23_p3_workflow_audit.sql` creates `ops.workflow_audit` (+ archive table). The migration exists in the repo but was never executed against the production Postgres (per `09-01-SUMMARY.md` blocker 1 cited in `.planning/v1.0-MILESTONE-AUDIT.md` INT-01).
- Why: No CD step applies migrations to the VPS. `.github/workflows/migration-validate.yml` applies migrations only to an ephemeral CI Postgres on `localhost` (lines 62–137), so CI is green while the VPS has no `ops.workflow_audit` table.
- Impact: `W_AUDIT_WRITE` INSERTs fail with relation-not-found. Audit hooks in W1/W2/W3 use `continueOnFail: true`, so failures are swallowed and no audit entries are ever created. Breaks **AUDIT-02, AUDIT-03, AUDIT-04** (FLOW-03/04/05).
- Fix approach: `docker exec current-postgres-1 psql -U strapi -d strapi < db/migrations/2026-03-23_p3_workflow_audit.sql`, then verify `W_AUDIT_WRITE` succeeds. Long term: add a VPS migration-apply step to the CD pipeline so repo migrations and VPS schema cannot diverge.

**SaaS modules/entitlements migration shares the same CI-only application risk (P1)**
- Issue: `db/migrations/2026-04-06_saas_modules_entitlements.sql` adds the `uq_tenant_module` unique constraint, four entitlement indexes, the `uq_product_module_key` constraint, and the `entitlement_audit_log` table. Like the Phase 3 migration, nothing in CD applies it to the VPS.
- Why: New SaaS multi-tenant work (commits `62f9af0`, `228b9bc`, `206da76`) relies on Strapi auto-creating `tenant_entitlements` / `product_modules` tables on boot, with this migration layering DB-level constraints Strapi does not enforce.
- Impact: Without the migration, `tenant_entitlements` has no `(tenant_id, module_key)` uniqueness — duplicate entitlement rows can accumulate (the seeder dedupes by `findOne`, but concurrent writes or manual admin edits can create duplicates that `W0_MODULE_GUARD`'s `data[0]` read silently masks). The `entitlement_audit_log` table is created but **has zero writers** anywhere in `workflows/` or `inventory-cms/` — dead schema with no audit coverage of entitlement changes.
- Fix approach: Apply the migration on the VPS; wire entitlement create/disable/expire events (admin dashboard + seeder) to write `entitlement_audit_log`, or drop the table until it is used.

**W_AUDIT_QUERY pagination and filters are non-functional (P1)**
- Issue: `W_AUDIT_QUERY` builds a `countQuery` in its parse step but has no second PG node to execute it, so `total: items.length` always returns the current-page row count (≤ 50). The UI sends `?status=...&channel=...` filters that the SQL ignores (no WHERE clause), and `AuditLogView.tsx` sends `limit` while the workflow reads `page_size` (backend defaults to 50).
- Why: Documented in `.planning/v1.0-MILESTONE-AUDIT.md` as WARN-01/02/03 and the Phase 07 tech-debt list.
- Impact: Audit log view shows "1 page" regardless of result set; status/channel filters appear to work in the UI but return unfiltered data. Misleading to operators investigating incidents.
- Fix approach: Add an execute node for `countQuery`; add WHERE clauses for `status`/`channel`; align the param name (`limit` vs `page_size`) between `admin-dashboard/src/pages/AuditLogView.tsx` and the workflow.

**`useEntitlements.ts` no-explicit-any lint debt (P2)**
- Issue: `admin-dashboard/src/hooks/useEntitlements.ts` uses `any` 6 times (`strapi.find<any>`, `(modRes as any)`, `m: any`, `e: any`, etc.). `admin-dashboard/eslint.config.js` extends `tseslint.configs.recommended`, which enables `@typescript-eslint/no-explicit-any`.
- Why: Hook was written quickly during the SaaS entitlement work to tolerate both Strapi v4/v5 response shapes (`m.attributes || m`).
- Impact: Pre-existing lint warnings; obscures real type errors in entitlement parsing. Four other components carry the same debt: `NotificationCenter.tsx`, `ToastProvider.tsx`, `AnalyticsView.tsx`, `AutomationView.tsx`, `AIChatBubble.tsx`.
- Fix approach: Define typed interfaces for `ProductModule` and `TenantEntitlement` responses; remove `any`. Low effort, isolated.

**Stale workflow fleet and tracked merge/screenshot artifacts (P2)**
- Issue: `workflows/` holds 100 JSON files; only ~77 are active on the VPS (per prior audits). A 132 KB binary PNG is committed at repo root as `--full-page` (a leading-dash filename that breaks naive shell tooling), and `conflicts.diff` (48 KB merge residue) is also tracked.
- Impact: Maintenance burden and confusion about which workflows are live; the dash-prefixed PNG can break scripts that glob the repo root. No functional impact today.
- Fix approach: `git rm -- ./--full-page conflicts.diff`; document each workflow's active status and remove confirmed dead code.

**admin-dashboard Dockerfile missing `RUN` keyword (P2)**
- Issue: `admin-dashboard/Dockerfile` line 28 reads `  touch /var/run/nginx.pid && chown nginx:nginx /var/run/nginx.pid` with no `RUN` prefix.
- Why: WARN-06 in `.planning/v1.0-MILESTONE-AUDIT.md`; **still present** in the current Dockerfile.
- Impact: The line is a no-op comment-continuation in cached builds; on a non-cached rebuild it can cause a build error or silently skip PID-file ownership, leaving the unprivileged nginx unable to write its pid file.
- Fix approach: Prefix with `RUN` and chain into the preceding `USER root` block.

---

## Known Bugs

**AuditLogView fetches an unrouted `/api/webhook/...` path (P0)**
- Symptoms: Admin dashboard "Audit Log" view returns nothing; requests never reach n8n.
- Trigger: Open the Audit Log page in the deployed admin dashboard.
- Root cause: `admin-dashboard/src/pages/AuditLogView.tsx:97` sets `apiBase = import.meta.env.VITE_API_URL || '/api'`, and line 112 builds `${apiBase}/webhook/v1/internal/audit-log`. `VITE_API_URL` is declared as an `ARG` in `admin-dashboard/Dockerfile` (line 11) but is **not passed in `docker-compose.hostinger.prod.yml`** — the admin-dashboard `build.args` block contains only `VITE_DOMAIN`, `VITE_STRAPI_URL`, `VITE_N8N_URL`. The baked value is empty → `apiBase` falls back to `/api` → final URL `/api/webhook/v1/internal/audit-log` is unrouted. A `n8nBase` variable is declared (line 96) but unused.
- Workaround: None.
- Fix: Add `VITE_API_URL: https://api.${DOMAIN_NAME}` to the admin-dashboard `build.args` in compose, rebuild the image, and apply the Phase 3 migration. (INT-03 / AUDIT-03; **confirmed unresolved** — build args verified missing on 2026-06-20.)

**Disk-usage alert never fires (`stat -f -c` incompatible with Alpine) (P1)**
- Symptoms: `DISK_ALERT` never emits even as the VPS fills.
- Trigger: Any W_QUEUE_METRICS run inside the Alpine/busybox-based n8n container.
- Root cause: `workflows/W_QUEUE_METRICS.json` computes disk usage via `require('child_process').execSync("stat -f -c '%a %s %b' /")`. The `-f -c` flags are GNU coreutils syntax; busybox `stat` rejects them, the exception is caught, `diskUsedPct` stays `-1`, and the alert guard `diskUsedPct >= 0` is never satisfied. Phase 07 had fixed this with `df -k /`; Phase 09 credential patching regressed it.
- Workaround: None (the metric silently reports -1).
- Fix: Replace the `stat -f -c` block with `df -k /` parsing (restore the Phase 07 fix). Breaks **METR-05** / FLOW-02; **confirmed still present** in the current file.

**W1_IN_WA.json `active: false` deployment trap (P1)**
- Symptoms: After importing workflows on the VPS, WhatsApp inbound processing is silently dead while Instagram (W2) and Messenger (W3) work.
- Trigger: Import `workflows/W1_IN_WA.json` without separately activating it in the n8n DB.
- Root cause: `workflows/W1_IN_WA.json` ships `"active": false`; `W2_IN_IG.json` and `W3_IN_MSG.json` ship `"active": true`. An importer that trusts the file's active flag leaves the primary channel disabled.
- Workaround: `UPDATE workflow_entity SET active = true WHERE name = 'W1_IN_WA'` after import.
- Fix: Set `"active": true` in the repo file (WARN-05). **Confirmed still false** on 2026-06-20.

**W_AUDIT_ARCHIVE not activated on VPS despite local fix (P1)**
- Symptoms: 90-day audit archive never runs; `ops.workflow_audit` (once created) grows unbounded.
- Trigger: n8n 2.x `scheduleTrigger` raised `propertyValues[itemName] is not iterable` on the original node.
- Root cause: Commit `8bd4c33` fixed the node locally and the repo file now ships `"active": true` (`workflows/W_AUDIT_ARCHIVE.json` line 3), but the workflow was never re-imported/activated on the VPS (INT-05 / AUDIT-04).
- Workaround: None.
- Fix: Re-import `W_AUDIT_ARCHIVE.json` on the VPS and `UPDATE workflow_entity SET active = true WHERE name = 'W_AUDIT_ARCHIVE'`.

---

## Security Considerations

**Secrets present in full git history — rotation outstanding (P0)**
- Risk: `.gitleaks.toml` (lines 108–121) suppresses **8 historical commits** (`a5b957e…`, `56a5516…`, `f16faf4…`, `6d08c8f…`, `0627abc…`, `cd133f1…`, `9c3ff52…`, `08541c4…`) that contained real secrets in now-deleted files (`.env`, `vps.env`, `vps_configs.txt`, `nemoclaw/.env`). The file's own comment states these exposed an **n8n encryption key, a Telegram bot token, and API keys** that "MUST be rotated on VPS."
- Current mitigation: Commits are allowlisted only to unblock CI scanning; the secrets remain readable to anyone who clones the repo (`git log -p` of those commits).
- Recommendations: Treat as compromised. Rotate the n8n encryption key, Telegram token, and all API keys exposed in those commits **on the VPS**. Re-encrypt n8n credentials after the key rotation. Consider history rewrite (`git filter-repo`) if the repo is or becomes externally accessible. Track completion — there is no evidence in the repo that rotation has occurred.

**Critical secrets still missing / unrotated (P1)**
- Risk: `SECRETS_ACTION_PLAN.md` lists `STRAPI_API_TOKEN` as 🔴 CRITICAL/MISSING (needed for n8n→CMS cortex auth and, notably, for `W0_MODULE_GUARD`'s `STRAPI_API_TOKEN_INTERNAL`). `WA_API_TOKEN`, `WA_PHONE_NUMBER_ID`, and the Instagram/Messenger/TikTok tokens are all marked MISSING. `SECRETS_INVENTORY.md` shows `REDIS_PASSWORD` as conditional/optional.
- Current mitigation: Partial values committed to plan docs (e.g. truncated `META_APP_SECRET`, `IG_APP_SECRET`); production channels cannot fully authenticate until the missing tokens are injected.
- Recommendations: Provision `STRAPI_API_TOKEN` first (it gates the module guard — see "Tenant isolation"). Make `REDIS_PASSWORD` mandatory and rotate quarterly. Establish a documented rotation cadence; `SECRETS_INVENTORY.md` has rotation TODOs but no schedule or owner.

**Tenant isolation is scaffolding-only; effectively single-tenant (P1)**
- Risk: The SaaS multi-tenant work (`tenant_entitlements`, `product_modules`, `W0_MODULE_GUARD`, `useEntitlements`) does not derive a real tenant from request context. `DEFAULT_TENANT_ID` is **not set** in `docker-compose.hostinger.prod.yml` or `.env.example`, so both `W0_MODULE_GUARD` (`workflows/W0_MODULE_GUARD.json`) and the seeder (`inventory-cms/src/bootstrap-seeds/saas-entitlements.ts:127`) fall back to the literal `'default'`. Every inbound message is evaluated against tenant `'default'`. There is no per-tenant data partitioning on orders/customers — tenant separation exists in entitlement tables only.
- Current mitigation: The guard's fail-closed behavior (below) limits *module* access but not *data* access. The unique constraint `uq_tenant_module` exists only if the SaaS migration is applied (it likely is not on the VPS — see Tech Debt).
- Recommendations: Before onboarding a second tenant, (1) derive `tenant_id` from the inbound channel identity / WABA phone-number-id rather than a global default; (2) add `tenant_id` scoping to order/customer queries; (3) ensure the SaaS migration's unique constraint is applied so a tenant cannot accumulate conflicting entitlements.

**Frontend entitlement check fails OPEN while the workflow guard fails CLOSED (P1)**
- Risk: `admin-dashboard/src/hooks/useEntitlements.ts:52-55` — `hasModule()` returns `true` whenever `loading` is true ("Fail-open for local dev or if loading"), and the `catch` on fetch failure (lines 42–44) leaves `modules` empty without surfacing an error. Meanwhile `workflows/W0_MODULE_GUARD.json` correctly fail-closes (`GUARD_ERROR_FAILCLOSED` denies on any exception). The two layers disagree on failure semantics.
- Current mitigation: The server-side guard is authoritative for workflow execution, so a fail-open UI cannot grant backend capability — but it will render modules/navigation a tenant is not entitled to, and Strapi 500s during entitlement fetch present as "all modules enabled."
- Recommendations: Default `hasModule` to `false` (or a known shared-core allowlist) on error/loading; show an explicit error state instead of silently granting access. Keep the UI gate consistent with the server's fail-closed posture.

**W0_MODULE_GUARD reads only `data[0]` and depends on an internal token (P2)**
- Risk: The guard queries Strapi by `module_key`/`tenant_id` and trusts `data?.[0]`. If `STRAPI_API_TOKEN_INTERNAL` is unset (it is referenced by exactly one workflow and is not confirmed present in compose), every guard call throws and fail-closes — denying **all** gated channels (WhatsApp, Instagram, Messenger, TikTok, voice, kiosk order, order finalizer). That is the safe direction, but it converts a missing-secret condition into a total inbound outage with the only signal being `GUARD_ERROR_FAILCLOSED` in logs.
- Current mitigation: Fail-closed prevents unauthorized access; 8 entrypoint workflows invoke the guard (`W1_IN_WA`, `W1_IN_TIKTOK`, `W2_IN_IG`, `W3_IN_MSG`, `W30_VOICE_CALL_INIT`, `W_KIOSK_ORDER`, `W_ORDER_FINALIZER`, plus the guard itself).
- Recommendations: Add an explicit alert when `GUARD_ERROR_FAILCLOSED` fires (distinct from a legitimate `NO_ENTITLEMENT` denial) so a missing/expired internal token is paged, not silently dropping all orders. Confirm `STRAPI_API_TOKEN_INTERNAL` is in the n8n env.

**Existing hardening to preserve (context)**
- Query-string token blocking, Authorization-header-only auth, Meta HMAC signature enforcement (`META_SIGNATURE_REQUIRED=enforce`), and SSE auth hardening (commit `c1883cf`) are in place per prior audits. The CI secret-scan (`.github/workflows/secret-scan.yml`) and `security-scan.yml` (Trivy, gitleaks, compose/nginx SAST) run on push/PR; container CVE scanning is report-only (`exit-code: 0`), so upstream HIGH/CRITICAL CVEs in n8n/postgres/redis/nginx/traefik images do not block. Periodically review Trivy artifacts manually.

---

## Performance Bottlenecks

**W0_MODULE_GUARD adds 2 synchronous Strapi round-trips to every inbound message (P1)**
- Problem: Each gated inbound message triggers `W0_MODULE_GUARD`, which makes up to two sequential `fetch()` calls to Strapi (`product-modules`, then `tenant-entitlements`) before the message is processed.
- Cause: No caching; the guard re-queries Strapi on every execution for module/entitlement state that changes rarely.
- Measurement: Not yet instrumented. Combined with the documented n8n webhook verification budget (Meta requires < 5 s; current latency ~2–3 s), the added guard latency erodes the buffer and risks Meta retries/suspension under queue pressure.
- Improvement path: Cache module/entitlement lookups in Redis (e.g. 5-min TTL keyed by `tenant_id:module_key`); invalidate on entitlement change. Instrument guard P95.

**W_QUEUE_METRICS cannot measure the very pressure it exists to detect (P1)**
- Problem: Because of the credential gap and broken disk check (above), queue depth, error rate, and disk usage are not observable in production.
- Cause: See Tech Debt / Known Bugs.
- Improvement path: Fix the credential IDs and disk check; then the existing thresholds (queue > 50 for 2 windows, disk > 80%) become meaningful.

**Strapi 5 cold start and single-worker n8n queue (P2, pre-existing)**
- Problem: Strapi CMS bootstrap takes 3–8 min on the 2-CPU VPS (the cause of the historical 39-restart crash loop; mitigated by `start_period: 180s`). A single `n8n-worker` with default `QUEUE_BULL_MAX_CONCURRENCY=2` processes all background jobs.
- Measurement: CMS bootstrap 3–8 min (`SRE_AUDIT_REPORT.md` Gap 1). Worker saturates at ~4 workflows/min sustained.
- Improvement path: Pre-bake CMS node_modules; raise worker concurrency or add a second worker; add the per-tenant entitlement cache to cut Strapi load.

---

## Fragile Areas

**Repo↔VPS schema drift (P0 root cause)**
- Why fragile: Migrations live in `db/migrations/` and are validated only against an ephemeral CI Postgres (`.github/workflows/migration-validate.yml`). Nothing applies them to the VPS, so the repo can claim a feature is "done" (green CI) while the production schema lacks the table/constraint. This single gap is the root cause of AUDIT-02/03/04 and now threatens the SaaS entitlement constraints.
- Common failures: `relation "ops.workflow_audit" does not exist`; missing `uq_tenant_module`; features that pass CI and silently no-op in production.
- Safe modification: Add a guarded VPS migration-apply step to CD; or maintain an explicit, idempotent "apply on VPS" runbook step and verify with a post-deploy schema check.
- Test coverage: CI idempotence test exists; **no test asserts the VPS schema matches the repo.**

**n8n credential references in workflow JSON (P0)**
- Why fragile: Credential IDs are embedded in workflow JSON either as literals (`1mZZJEscADgQ8InR`) or as `$env.*` expressions. A re-export, merge, or "patch" can silently swap a working literal for an empty expression (exactly what happened to W_QUEUE_METRICS in Phase 09).
- Common failures: Node fails with credential-not-found; with `continueOnFail` the failure is swallowed.
- Safe modification: Standardize on one approach (literals OR env vars consistently); add a CI lint that rejects `id: "={{$env...}}"` credential expressions, or asserts referenced env vars exist in compose.
- Test coverage: None for credential resolution.

**continueOnFail-masked audit hooks (P1)**
- Why fragile: W1/W2/W3 audit-write hooks use `continueOnFail: true`. This is correct for not blocking order flow, but it means an entire class of failures (missing table, bad credential) produces zero signal.
- Safe modification: Keep `continueOnFail`, but route the failure branch to a counter/alert so silent audit loss is detectable.
- Test coverage: None.

**SaaS module-key alignment across three sources (P2)**
- Why fragile: Module keys must match exactly across `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts`, `config/product_modules.json`, and the `module_key` values workflows pass to `W0_MODULE_GUARD`. The seeder's own comment warns "any mismatch will cause the guard to deny access." Commit `206da76` was a "module key alignment" fix, indicating this has already drifted once.
- Common failures: A typo'd `module_key` in a workflow → `NO_ENTITLEMENT` → channel silently denied.
- Safe modification: Add a CI check that every `module_key` referenced in `workflows/` exists in the seed list.
- Test coverage: None.

---

## Scaling Limits

**Disk / ENOSPC on the 119 GB single VPS (P1)**
- Current capacity: ~54% used at the 2026-03-23 audit (45 GB free); npm cache + Docker layer growth fills it within days of a Strapi rebuild.
- Limit: Below ~5 GB free, ENOSPC truncates JSON files (workflows, config) to 0 bytes — confirmed previously and effectively unrecoverable without restore.
- Symptoms at limit: 0-byte config/workflow files; container start failures; corrupted writes.
- Scaling path: `scripts/disk-cleanup.sh` (threshold-gated at 75%) + the `0 2 * * *` cron from `scripts/setup-vps-sre.sh` mitigate this **only if installed on the VPS** (a P0 manual action in `SRE_AUDIT_REPORT.md` §5). The W_QUEUE_METRICS disk alert that should warn before the limit is currently broken (see Known Bugs). Verify the cleanup cron is installed and the disk alert is fixed; consider a disk upgrade.

**No swap + 448 MB free RAM (P1)**
- Current capacity: 0 B swap, ~448 MB free RAM at audit time.
- Limit: An n8n/Strapi spike can OOM-kill a container with no swap cushion.
- Scaling path: Add a 2 GB swapfile (P1 manual action in `SRE_AUDIT_REPORT.md` §5, not yet confirmed applied).

**Single n8n worker / Redis outbox (P2)**
- Current capacity: 2 concurrent workflows/worker; Redis allocated 256 MB with `allkeys-lru`.
- Limit: Sustained arrival > ~4 workflows/min backs up the queue; > ~100k daily outbound messages can exhaust Redis. The broken queue-depth metric means this is currently unobservable.
- Scaling path: Fix metrics first, then raise concurrency / add a worker / batch Redis writes as needed.

---

## Dependencies at Risk

**n8n 2.9.4 (maintenance mode; 2.x→3.x debt) (P2)**
- Risk: n8n 2.x is in maintenance mode. The `scheduleTrigger` incompatibility (`propertyValues[itemName] is not iterable`) that broke W_AUDIT_ARCHIVE is a 2.x-era bug; container CVE scanning for `docker.n8n.io/n8nio/n8n:2.9.4` is report-only.
- Impact: Future workflow/credential schema changes on upgrade; lingering 2.x node bugs.
- Migration plan: Stage a 3.x upgrade on a branch; re-validate webhook paths, queue mode, and all entrypoint workflows; verify the encryption key (post-rotation) decrypts credentials.

**Strapi 5 auto-table reliance for SaaS (P2)**
- Risk: The SaaS feature depends on Strapi creating `tenant_entitlements` / `product_modules` from content-type schemas on boot, with constraints added by a separate migration. If schema and migration drift, constraints silently never apply.
- Impact: Loss of entitlement uniqueness; duplicate rows masked by `data[0]` reads.
- Migration plan: Treat the SaaS migration as required deployment state; verify constraints post-deploy.

*(Note: the prior CONCERNS.md "Node 18 EOL" item is resolved — `admin-dashboard/Dockerfile`, `kiosk-app/Dockerfile`, and `inventory-cms/Dockerfile` now use `node:20-alpine` / `node:20.18.3-alpine`.)*

---

## Operational Risks

**Off-VPS backup depends on unverified secrets (P1)**
- Risk: `.github/workflows/scheduled-backup.yml` runs daily and now includes a GPG-encrypted S3 `upload-offsite` job (PATCHLOG 2026-03-21), but **silently warns and skips** if `VPS_SSH_KEY` is unset (line 77) and requires `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `BACKUP_GPG_PASSPHRASE`, and S3 vars to be configured. The 2026-03-23 audit found only a single 4-day-old, VPS-only dump and no completed restore drill.
- Impact: If the disk fails or ENOSPC corrupts data, the live DB and the only backup can be lost together.
- Recommendations: Confirm `VPS_SSH_KEY` + S3 secrets are set in GitHub Actions; run `scripts/restore_drill.sh` to prove restorability; verify a recent off-site dump exists.

**VPS SRE tooling exists in-repo but may be uninstalled (P1)**
- Risk: `container-watchdog.sh`, `disk-cleanup.sh`, `daemon.json` (log rotation + `live-restore`), and `post-deploy-verify.sh` are committed, but installing them is a P0 *manual* action in `SRE_AUDIT_REPORT.md` §5 (cron install, `ALERT_WEBHOOK_URL`, `daemon.json` copy). With `restart: unless-stopped` and no retry cap, a crash loop (like the historical 39-restart CMS loop) recurs silently without the watchdog.
- Recommendations: Verify on the VPS that the cron jobs are installed, `ALERT_WEBHOOK_URL` is set in `/opt/resto/current/.env`, and `/etc/docker/daemon.json` is in place.

**Phase 09 unverified; Nyquist non-compliant phases (P2)**
- Risk: `.planning/v1.0-MILESTONE-AUDIT.md` records Phase 09 `VERIFICATION.md` as missing (INT-04) and Phases 01/07/09/10 `VALIDATION.md` as draft (`nyquist_compliant: false`), with Phase 03 `VALIDATION.md` missing entirely. ROADMAP.md and REQUIREMENTS.md checkboxes are stale relative to the actual SUMMARY/VERIFICATION state.
- Impact: The documented "done" state overstates runtime reality (27/34 reqs at code level, but 7 broken at VPS runtime).
- Recommendations: Create Phase 09 VERIFICATION.md documenting the VPS-partial state; reconcile ROADMAP/REQUIREMENTS checkboxes against runtime truth so future planning isn't misled.

---

## Test Coverage Gaps

**VPS runtime vs CI divergence (P0)**
- What's not tested: Whether migrations are actually present on the VPS, whether n8n credential references resolve in production, and whether workflows are *active* on the VPS (not just `active` in the repo file).
- Risk: Green CI with broken production — the exact failure mode behind METR-01/02/04/05 and AUDIT-02/03/04.
- Priority: High. Add a post-deploy smoke that asserts: `ops.workflow_audit` exists, `W_QUEUE_METRICS` emits a non-`-1` disk metric, `W1_IN_WA` is active, and the audit-log endpoint returns 200 via the gateway.

**Entitlement / tenant-isolation behavior (P1)**
- What's not tested: That `W0_MODULE_GUARD` denies a non-entitled module, fail-closes on Strapi error, and that the UI gate (`useEntitlements`) hides modules consistently with the backend.
- Risk: Silent over-grant (UI fail-open) or total outage (guard fail-closed on missing token) ship undetected.
- Priority: High.

**Module-key drift, audit hooks, and W_AUDIT_QUERY filters (P2)**
- What's not tested: Module-key consistency across seed/config/workflows; that audit-write failures are surfaced; that audit-log status/channel filters actually filter.
- Risk: Channels silently denied; audit data silently lost; misleading audit UI.
- Priority: Medium.

---

*Concerns audit: 2026-06-20 — supersedes the 2026-03-28 version. Severity tags reflect VPS-runtime impact, not just code presence.*
