# Codebase Concerns

**Analysis Date:** 2026-03-20

## Tech Debt

**db-migrate init container uses `service_started` not `service_healthy` for postgres:**
- Issue: `db-migrate` depends on postgres with `condition: service_started`, but postgres may not be ready to accept connections when the container starts
- Files: `project/docker-compose.hostinger.prod.yml` line 170
- Impact: Intermittent migration failures on cold boot or after postgres restarts; migrations may silently time out
- Fix approach: Change to `condition: service_healthy` matching the pattern used by `n8n-main` and `cms`

**Backup stored only on VPS local disk (no off-site copy):**
- Issue: `scheduled-backup.yml` creates pg_dump files at `/opt/resto/backups/` on the VPS itself. If the VPS disk fails, or ENOSPC occurs, both the live data and backup are lost.
- Files: `project/.github/workflows/scheduled-backup.yml`, `project/scripts/backup_postgres.sh`
- Impact: Total data loss on disk failure. Retention is also limited (7 daily, 4 weekly).
- Fix approach: Add S3/R2/B2 off-site backup step in `scheduled-backup.yml`; encrypt before upload

**n8n task-runner still spawns despite `N8N_RUNNERS_ENABLED=false`:**
- Issue: n8n 2.9.4 spawns internal task-runner sub-processes regardless of `N8N_RUNNERS_ENABLED=false` (env var not fully honored). This caused VPS load spike (28 → 9.8) observed in session 2026-03-14.
- Files: `project/docker-compose.hostinger.prod.yml` lines 377, 518
- Impact: Unpredictable CPU spikes on the single-node VPS; may cause 1G RAM n8n-main to OOM under concurrent load
- Fix approach: Upgrade n8n to a version where the env var is fully respected, or configure via `N8N_RUNNERS_*` additional flags

**Admin dashboard VITE_STRAPI_URL baked at build time:**
- Issue: `admin-dashboard` Dockerfile receives `VITE_STRAPI_URL=https://cms.<domain>` as a build arg. If the CMS URL changes, a full image rebuild is required.
- Files: `project/docker-compose.hostinger.prod.yml` lines 13, `project/admin-dashboard/Dockerfile`
- Impact: Every domain change requires image rebuild + redeployment
- Fix approach: Serve config via a `/config.js` endpoint at runtime, or proxy CMS through gateway and use the stable `api.<domain>/v1/portal/` path (already implemented for admin API calls)

**Migration naming inconsistency (two formats coexist):**
- Issue: Older migrations use numeric prefixes (`006_`, `010_`, `013_`); newer ones use date prefixes (`2026-01-22_*`). Sort order relies on filenames.
- Files: `project/db/migrations/` (all files)
- Impact: A new numeric migration like `007_*` would sort before `2026-01-22_*` migrations, potentially breaking FK-dependent migration order
- Fix approach: Rename all remaining numeric-prefixed migrations to date-prefixed format; update `integrity_gate.sh` checks

**`integrity_gate.sh` only validates inbound adapter workflows (W1/W2/W3):**
- Issue: Security invariants (token gating, `scopeOk` enforcement, tenant isolation via `restaurant_id`) are only validated for `W1_IN_WA.json`, `W2_IN_IG.json`, `W3_IN_MSG.json`. The 88 other workflows have no automated security property checks.
- Files: `project/scripts/integrity_gate.sh`
- Impact: A developer could accidentally commit a workflow that leaks data across tenants or skips auth
- Fix approach: Extend integrity gate to check all workflows that access Strapi with tenant filters

**Bootstrap SQL and migrations overlap:**
- Issue: `db/bootstrap.sql` is described as "merges bootstrap.sql + all 26 migrations into a single idempotent file", meaning the same schema exists in two places. CI applies both (`Apply bootstrap schema` then `Apply all migrations`), with warnings expected for overlaps.
- Files: `project/db/bootstrap.sql`, `project/db/migrations/`, `project/.github/workflows/ci.yml` lines 276-318
- Impact: CI is noisy (migration warnings are expected); bootstrap.sql can drift from the migrations if not manually kept in sync
- Fix approach: Remove overlap; either bootstrap.sql is authoritative OR migrations are authoritative, not both

**`strapi_admin_password` passed as file path, not file content:**
- Issue: In compose, `STRAPI_SUPER_ADMIN_PASSWORD=/run/secrets/strapi_admin_password` sets the env var to the FILE PATH rather than mounting the file as a Docker secret. Strapi likely reads this as a literal string.
- Files: `project/docker-compose.hostinger.prod.yml` line 105
- Impact: Strapi admin password may not be set from the secrets file as intended (risk of weak/default password)
- Fix approach: Use `STRAPI_SUPER_ADMIN_PASSWORD_FILE` pattern if Strapi supports it, or read the file in an entrypoint wrapper

## Security Considerations

**`ADMIN_ALLOWED_IPS` is a single shared allowlist for all private services:**
- Risk: One IP allowlist governs access to n8n console, CMS admin, admin dashboard, and internal API routes. If any allowed IP is compromised (laptop, VPN), all private services are exposed simultaneously.
- Files: `project/docker-compose.hostinger.prod.yml` (all Traefik `ipallowlist.sourcerange` labels)
- Current mitigation: BasicAuth provides a second factor for console and admin-dashboard; CMS only has IP allowlist
- Recommendations: Add per-service allowlists; add BasicAuth to CMS route

**Cosign signing with `continue-on-error: true`:**
- Risk: Cosign signing step in `build-push-artifacts.yml` uses `continue-on-error: true`, meaning image signing silently fails if the `COSIGN_PRIVATE_KEY` secret is not configured. The unsigned image is still pushed.
- Files: `project/.github/workflows/build-push-artifacts.yml` lines 112, 128, 138
- Current mitigation: SBOM and SLSA attestations also have `continue-on-error: true`
- Recommendations: Remove `continue-on-error` once Cosign secret is confirmed configured; add a verification step

**n8n console exposed to proxy network (Traefik label present):**
- Risk: n8n-main is on both `proxy` and `internal` networks. The Traefik label routes `console.<domain>` to it. If Traefik middleware chain is misconfigured, the n8n editor could be public.
- Files: `project/docker-compose.hostinger.prod.yml` lines 453-469
- Current mitigation: `console-chain` applies IP allowlist + BasicAuth
- Recommendations: Periodic smoke test that `console.<domain>` returns 401/403 from non-allowlisted IP

**Traefik dashboard enabled (`--api.dashboard=true`):**
- Risk: Traefik dashboard at `:8080` is bound to `127.0.0.1:8080` only on the host, but the configuration enables it. If an SSRF or local privilege escalation exists, it could be reached.
- Files: `project/docker-compose.hostinger.prod.yml` lines 722, 754
- Current mitigation: Port bound to `127.0.0.1:8080` (localhost only)
- Recommendations: Acceptable; verify dashboard auth is also enforced if accessed via SSH tunnel

**CMS route only has IP allowlist — no BasicAuth:**
- Risk: Strapi admin panel at `cms.<domain>` is only protected by IP allowlist, not BasicAuth. CMS auth is entirely application-level (Strapi admin login).
- Files: `project/docker-compose.hostinger.prod.yml` line 134 (`cms-chain` has no `basicauth` middleware)
- Current mitigation: IP allowlist + Strapi's own session-based authentication
- Recommendations: Add BasicAuth to `cms-chain` as a defense-in-depth layer

## Performance Bottlenecks

**Single VPS node for all 12 containers:**
- Problem: All services compete for CPU and RAM on a single 2-vCPU, ~4 GB RAM VPS
- Files: `project/docker-compose.hostinger.prod.yml` (resource limits sum: ~5.25 CPU, ~5 GB RAM — over-provisioned relative to physical limits)
- Cause: Resource limits are maximums, not guarantees; under concurrent load (n8n-worker processing + Strapi + postgres) all three can spike simultaneously
- Improvement path: Migrate postgres to separate managed DB or VPS; consider n8n-worker on separate node

**n8n-worker concurrency limited to 2:**
- Problem: `QUEUE_BULL_MAX_CONCURRENCY=2` means at most 2 workflows execute simultaneously in the worker
- Files: `project/docker-compose.hostinger.prod.yml` line 519
- Cause: VPS CPU/RAM constraint intentional limit
- Improvement path: Increase to 4 after moving postgres to dedicated instance and verifying RAM headroom

**Nginx DNS cache causing 502 after CMS container restarts:**
- Problem: nginx caches the CMS IP at startup; after `cms` container recreation gets new Docker IP, all `/v1/strapi/*` requests return 502 until nginx is reloaded
- Files: `project/infra/gateway/nginx.conf` lines 71-72
- Cause: nginx resolver `valid=10s` limits cache, but if gateway container was restarted before the fix was applied to the running container, old conf persists
- Improvement path: Ensure gateway container uses the committed `nginx.conf` (requires container recreation, not just `nginx -s reload` if old container is still using old bind mount)

## Fragile Areas

**CMS (Strapi) — single point of failure for all services:**
- Files: `project/inventory-cms/`, `project/docker-compose.hostinger.prod.yml` cms service
- Why fragile: If CMS is down, n8n workflows cannot fetch menu config, kiosk cannot display products, admin dashboard is degraded. Platform-wide degradation is immediate.
- Safe modification: Always test CMS changes with `curl http://127.0.0.1:1337/_health` before restarting; always rebuild image locally first
- Test coverage: Basic healthcheck exists; no automated test for Strapi API responses

**Gateway nginx.conf bind mount path dependency:**
- Files: `project/infra/gateway/nginx.conf`
- Why fragile: Running gateway container may be using stale bind mount from old VPS path (`/root/project/`) if it has never been recreated since CD started managing `/opt/resto/current/`. Changes to the nginx.conf file will not take effect until `docker compose up -d gateway` recreates the container.
- Safe modification: Always recreate gateway container after nginx.conf changes: `docker compose -f docker-compose.hostinger.prod.yml up -d gateway`

**n8n encryption key must not change:**
- Files: `project/secrets/n8n_encryption_key`
- Why fragile: All n8n credentials are encrypted with this key. Changing or losing it makes all stored credentials unreadable. n8n will crash on startup if the key changes.
- Safe modification: Never rotate without a full credential re-encryption plan

**DB bootstrap SQL overlapping with migrations:**
- Files: `project/db/bootstrap.sql`, `project/db/migrations/`
- Why fragile: The CI warns on overlap but continues. If bootstrap.sql diverges from migrations, a fresh install via bootstrap.sql will have a different schema than an incremental migration path. This can cause subtle production vs. test environment drift.
- Test coverage: Partial — CI tests migration idempotence but not bootstrap-vs-migration equivalence

## Scaling Limits

**VPS disk (119 GB):**
- Current capacity: 119 GB total; can fill quickly from Docker layer cache, logs, and postgres WAL
- Limit: ENOSPC corrupts files to 0 bytes (observed: npm cache, Strapi dist files corrupted)
- Scaling path: Scheduled cleanup (`docker system prune`), log rotation (already configured), off-site backup to free local space. Consider Hostinger volume expansion.

**PostgreSQL max_connections=100:**
- Current capacity: 100 total connections; n8n-main + n8n-worker + Strapi all compete
- Limit: Connection exhaustion causes 503s on all services simultaneously
- Scaling path: Add PgBouncer connection pooler; or increase to 150 if RAM allows

**Redis 256 MB max memory (effective limit 384 MB container):**
- Current capacity: Bull queue + any Redis caching
- Limit: If Bull queue backlog grows (e.g. Meta sends burst of messages), Redis may evict queue entries
- Scaling path: Increase container memory limit; configure `maxmemory-policy noeviction` for queue data safety

## Dependencies at Risk

**n8n 2.9.4 — `N8N_RUNNERS_ENABLED=false` not fully honored:**
- Risk: Task-runner processes spawn regardless; env var behavior may change in minor updates
- Impact: CPU spikes on update; potential workflow execution changes
- Migration plan: Monitor n8n changelog for runner fixes; test `N8N_RUNNERS_ENABLED` behavior before any n8n upgrade

**Whisper ASR image pinned to `v1.2.0` (not SHA-pinned):**
- Risk: Tag could be reused by upstream; supply chain attack surface
- Files: `project/docker-compose.hostinger.prod.yml` line 766 (comment acknowledges risk)
- Impact: If tag is overwritten, production container would run malicious code on next pull
- Migration plan: Add SHA digest to whisper image pin (same as other images should use SHA in prod)

**Ollama 0.6.2 port 11434 published to host:**
- Risk: Port 11434 is published to the VPS host (`"11434:11434"`), making Ollama accessible to anyone who can reach the VPS IP on that port (firewall permitting)
- Files: `project/docker-compose.hostinger.prod.yml` lines 610-611
- Impact: Unauthorized LLM inference; resource exhaustion
- Migration plan: Change to `127.0.0.1:11434:11434` to restrict to localhost only

## Missing Critical Features

**No off-site database backup:**
- Problem: Backups only stored locally on VPS at `/opt/resto/backups/`. No S3/R2/Backblaze copy.
- Blocks: Recovery from VPS failure or disk corruption

**No structured distributed tracing (correlation IDs at gateway layer):**
- Problem: nginx `json_audit` log does not inject an `X-Request-ID` or correlation ID. n8n workflows generate `correlation_id` internally but it is not tied to the gateway access log.
- Files: `project/infra/gateway/nginx.conf` (log format at lines 46-55)
- Blocks: Cross-service request tracing; debugging complex multi-hop failures

**No automated test for CMS API responses:**
- Problem: No smoke test verifies that Strapi returns valid menu/order data; only the `_health` endpoint is checked.
- Blocks: Detecting Strapi content schema regressions after CMS rebuilds

## Test Coverage Gaps

**n8n workflows — no unit-level tests:**
- What's not tested: Individual workflow node logic (JavaScript code nodes), edge cases in cart management, payment routing, fraud detection
- Files: `project/workflows/` (all 91 files)
- Risk: Workflow regressions are only caught by end-to-end smoke tests or production incidents
- Priority: High — business logic lives in workflow code nodes

**Admin dashboard — no component tests:**
- What's not tested: React component rendering, API client error handling, auth token refresh logic
- Files: `project/admin-dashboard/src/`
- Risk: UI regressions in admin operations panel go undetected until manual testing
- Priority: Medium

**Kiosk app — no component tests:**
- What's not tested: Cart flow, product display, order submission
- Files: `project/kiosk-app/src/`
- Risk: Customer-facing ordering flow could break silently
- Priority: Medium

**Outbox/DLQ integration — limited smoke coverage:**
- What's not tested: Full message lifecycle from inbound → outbox → retry → DLQ under failure conditions
- Files: `project/workflows/W15_OUTBOX_WORKER.json`, `W8_DLQ_HANDLER.json`
- Risk: Outbox failure modes (Redis outage, n8n crash mid-execution) not validated
- Priority: High

**Security boundary tests — IP allowlist bypass not tested:**
- What's not tested: Whether Traefik IP allowlist correctly blocks non-allowlisted IPs from `console.*`, `cms.*`, `admin.*`
- Files: `project/scripts/smoke_security.sh`, `project/scripts/smoke_security_gateway.sh`
- Risk: Misconfiguration of `ADMIN_ALLOWED_IPS` could silently expose private services
- Priority: High — recommend adding to post-deploy smoke suite

---

*Concerns audit: 2026-03-20*
