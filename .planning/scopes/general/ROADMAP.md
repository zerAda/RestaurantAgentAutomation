# General / Platform ROADMAP

**Scope:** Platform-wide concerns — not tied to a single service feature.
**Stack:** Docker Compose 12-service VPS (Traefik + nginx + n8n + Strapi + Postgres + Redis)
**Domain:** `srv1258231.hstgr.cloud` | VPS: `72.60.190.192`
**Updated:** 2026-03-20

---

## Priority Summary

| Priority | Phase | Theme | Blocker if skipped |
|----------|-------|-------|--------------------|
| P0 | 01 | Data Protection — off-site backup + restore drill | Total data loss on disk failure |
| P0 | 02 | Reliability — Redis eviction policy, disk alerting, `db-migrate` healthcheck fix | Queue corruption; ENOSPC silent corruption |
| P1 | 03 | Node.js 18→20 upgrade across all Dockerfiles | EOL image; unpatched CVEs in image layer |
| P1 | 04 | Observability — correlation IDs, structured JSON logs at gateway | Requests untraceable across services |
| P2 | 05 | Security hardening — CMS BasicAuth, Ollama host binding, Cosign enforcement | Defense-in-depth gaps |
| P2 | 06 | CI/CD supply chain — SHA-pin all 12 images, remove `continue-on-error` from Cosign | Silent supply chain failure |
| P3 | 07 | Operations — full nginx routing smoke suite, secret rotation runbook | Ops blind spots |

---

## Phase Definitions

---

### Phase 01: Data Protection — Automated Off-Site Backup + Restore Drill

**Goal:** Every daily and weekly backup is automatically uploaded to an S3-compatible bucket and verified. A restore drill confirms recovery is possible within 30 minutes.

**Context:** `scheduled-backup.yml` creates `pg_dump` files only on the VPS local disk (`/opt/resto/backups/`). If the 119 GB VPS disk fails or hits ENOSPC, both live data and the backup are lost simultaneously. There is no off-site copy, no encryption-at-rest for backups, and no documented restore drill.

**Success Criteria:**
- `scheduled-backup.yml` uploads each backup to `S3_BACKUP_BUCKET` after local integrity check
- Upload step is gated (fails the workflow if upload fails — not `continue-on-error`)
- Backup file is GPG-encrypted before upload (`BACKUP_ENCRYPT=true` path already exists in `backup_postgres.sh`)
- A restore drill script (`scripts/restore_drill.sh`) pulls the latest off-site backup, decrypts, restores to a temporary DB container, and verifies row counts match
- `docs/BACKUP_RESTORE.md` documents the full procedure with commands
- `RUNBOOK.md` updated with "Restore from off-site backup" section

**Requirements:** BAK-01, BAK-02, BAK-03

**Plans:**
- [ ] 01-PLAN.md — Add S3 upload step to `scheduled-backup.yml` + encryption gate
- [ ] 02-PLAN.md — Write `scripts/restore_drill.sh` + update `docs/BACKUP_RESTORE.md` and `RUNBOOK.md`

**Dependencies:** None (standalone)

---

### Phase 02: Reliability — Redis Eviction Policy, Disk Alerting, db-migrate Healthcheck

**Goal:** Three low-risk reliability fixes that prevent silent data corruption and service outages: configure Redis to never evict queue entries, add VPS disk pressure alerting before ENOSPC, and fix the `db-migrate` init container to wait for Postgres to be healthy before running migrations.

**Context:**
- Redis `entrypoint.sh` already sets `maxmemory 256mb --maxmemory-policy allkeys-lru` — this evicts the oldest keys (including Bull queue jobs) under memory pressure. For a queue broker, `noeviction` is correct so jobs are never silently dropped.
- `db-migrate` depends on postgres with `condition: service_started` (CONCERNS.md line 9) but postgres may not be accepting connections yet, causing intermittent migration failures on cold boot.
- `health-monitor.yml` checks only `GET /healthz` (HTTP 200); it does not alert on disk pressure. ENOSPC at 119 GB is a documented risk.

**Success Criteria:**
- Redis `entrypoint.sh` uses `--maxmemory-policy noeviction` (queue jobs are never evicted)
- `docker-compose.hostinger.prod.yml` `db-migrate` service uses `condition: service_healthy` for the postgres dependency
- A disk pressure check is added to `health-monitor.yml`: SSH step checks `df -h /` and fires `ALERT_WEBHOOK_URL` if usage exceeds 85%
- All three changes verified by smoke test commands documented in `TEST_REPORT.md`

**Requirements:** REL-01, REL-02, REL-03

**Plans:**
- [ ] 01-PLAN.md — Fix Redis eviction policy + fix `db-migrate` healthcheck dependency
- [ ] 02-PLAN.md — Add disk pressure alerting to `health-monitor.yml`

**Dependencies:** None (standalone)

---

### Phase 03: Node.js 18→20 Upgrade Across All Dockerfiles

**Goal:** All three custom Docker images (`cms`, `admin-dashboard`, `kiosk-app`) use `node:20-alpine` base images instead of `node:18-alpine`. Node.js 18 reached EOL April 2025; unpatched CVEs in the base layer accumulate.

**Context:** CI already uses `NODE_VERSION: "20"` (STACK.md line 19). The three `Dockerfile`s in `inventory-cms/`, `admin-dashboard/`, and `kiosk-app/` may still reference `node:18-alpine`. The upgrade is a 1-line change per Dockerfile, but requires image rebuilds and a smoke check to confirm the services start correctly.

**Success Criteria:**
- `project/inventory-cms/Dockerfile` base image is `node:20-alpine` (not 18)
- `project/admin-dashboard/Dockerfile` base image is `node:20-alpine`
- `project/kiosk-app/Dockerfile` base image is `node:20-alpine`
- `scripts/smoke.sh` or manual `curl https://cms.<domain>/_health` returns 204 after rebuild
- `project/VERSION` bumped and `PATCHLOG.md` entry added

**Requirements:** SEC-01

**Plans:**
- [ ] 01-PLAN.md — Update all three Dockerfiles + bump VERSION + PATCHLOG entry

**Dependencies:** None (standalone; can run parallel with Phase 02)

---

### Phase 04: Observability — Correlation IDs + Structured Logs

**Goal:** Every inbound request receives an `X-Request-ID` header injected by nginx and carried through to n8n workflow logs, making multi-hop request tracing possible.

**Context:** The nginx `json_audit` log format (nginx.conf lines 46–55) does not include a correlation ID field. n8n workflows generate `correlation_id` internally but it is not tied to the gateway access log entry. Without this link, debugging a failed inbound webhook requires correlating nginx logs (by IP + timestamp) with n8n execution logs manually.

**Success Criteria:**
- `nginx.conf` log format includes `"req_id":"$request_id"` field
- nginx injects `X-Request-ID: $request_id` header on all proxied requests
- `json_audit` log format updated: field added between `"rt"` and closing brace
- Gateway container recreated to apply new config
- A test request to `/healthz` produces an nginx log line with a non-empty `req_id`
- `ENV_REFERENCE.md` updated noting the new log field
- `RUNBOOK.md` "Debugging a request" section updated with grep instructions

**Requirements:** OBS-01, OBS-02

**Plans:**
- [ ] 01-PLAN.md — Add `$request_id` to nginx log format + inject header + recreate gateway

**Dependencies:** Phase 03 (Node.js upgrade) should be done first to avoid rebuilding images twice, but this phase is strictly infrastructure — it does not require a CMS or app rebuild.

---

### Phase 05: Security Hardening — CMS BasicAuth, Ollama Localhost Binding, Cosign Gate

**Goal:** Close three documented security gaps: add BasicAuth to the `cms-chain` Traefik middleware (defense-in-depth for the Strapi admin panel), restrict Ollama port 11434 to localhost only, and verify Cosign signing is enforced (not silently skipped).

**Context:**
- CONCERNS.md: `cms-chain` has no `basicauth` middleware — IP allowlist is the only perimeter for the Strapi admin panel. If an allowlisted IP is compromised, the CMS is fully exposed.
- CONCERNS.md: Ollama port `11434` is published `"11434:11434"` (0.0.0.0) in compose — unauthorized LLM inference / resource exhaustion from the internet (if VPS firewall has port open).
- CONCERNS.md: `build-push-artifacts.yml` has `continue-on-error: true` on Cosign signing — unsigned images can be pushed silently.

**Success Criteria:**
- `docker-compose.hostinger.prod.yml` `cms` service Traefik labels include `basicauth` middleware in the `cms-chain`
- Ollama port binding changed from `"11434:11434"` to `"127.0.0.1:11434:11434"`
- `build-push-artifacts.yml` Cosign signing steps have `continue-on-error` removed (or changed to `false`)
- `PATCHLOG.md` + `RUNBOOK.md` updated
- Smoke test confirms `cms.<domain>` returns 401 without BasicAuth credentials

**Requirements:** SEC-02, SEC-03, SEC-04

**Plans:**
- [ ] 01-PLAN.md — CMS BasicAuth addition + Ollama localhost binding
- [ ] 02-PLAN.md — Cosign `continue-on-error` removal + CI verification step

**Dependencies:** None (standalone)

---

### Phase 06: CI/CD Supply Chain — SHA-Pin All 12 Images + Strapi Secret Fix

**Goal:** All 12 Docker Compose services use SHA-pinned images (not just tag-pinned), and the `strapi_admin_password` secret file is read correctly at container startup instead of passing the file path as a string.

**Context:**
- STACK.md: infrastructure images (traefik, nginx, postgres, redis, ollama, whisper) are version-pinned but not SHA-pinned in `docker-compose.hostinger.prod.yml`. SHA-pinning prevents a compromised upstream tag from introducing malicious code.
- CONCERNS.md: `STRAPI_SUPER_ADMIN_PASSWORD=/run/secrets/strapi_admin_password` sets the env var to the FILE PATH — Strapi reads it as a literal string `"/run/secrets/strapi_admin_password"`.
- The Whisper image `v1.2.0` is noted in CONCERNS.md as not SHA-pinned.

**Success Criteria:**
- `docker-compose.hostinger.prod.yml` all 6 infrastructure images include `@sha256:...` digest after the tag
- `cms` service uses an entrypoint wrapper that reads `STRAPI_SUPER_ADMIN_PASSWORD` from the file and exports the actual secret value
- CI pipeline `security-scan.yml` or `build-push-artifacts.yml` verifies image digests post-pull
- `PATCHLOG.md` entry added

**Requirements:** SUP-01, SUP-02

**Plans:**
- [ ] 01-PLAN.md — Resolve and record SHA digests for all 6 infrastructure images; update compose
- [ ] 02-PLAN.md — Fix `STRAPI_SUPER_ADMIN_PASSWORD` file-path bug with entrypoint wrapper

**Dependencies:** None (standalone)

---

### Phase 07: Operations — Full Nginx Routing Smoke Suite + Secret Rotation Runbook

**Goal:** A comprehensive smoke test script covers all 8 nginx routing zones and all 5 Traefik chains. A secret rotation runbook documents step-by-step how to rotate each of the 4 Docker file secrets without causing downtime.

**Context:**
- CONCERNS.md: `smoke_security.sh` and `smoke_security_gateway.sh` exist but do not cover all 8 rate-limit zones or verify that private routes correctly reject non-allowlisted IPs.
- No documented procedure for rotating `postgres_password`, `n8n_encryption_key`, `traefik_usersfile`, or `strapi_db_password`. The n8n encryption key in particular cannot be rotated without a credential re-encryption plan.

**Success Criteria:**
- `scripts/smoke_all_routes.sh` tests all public and private routes: healthz, inbound webhook (WA/IG/MSG), strapi proxy, kiosk, admin, console, cms — and verifies correct HTTP status codes
- `scripts/smoke_all_routes.sh` is integrated into `cd-deploy.yml` post-deploy smoke step
- `docs/SECRET_ROTATION.md` documents rotation procedure for each of the 4 secrets with exact commands and rollback steps
- `RUNBOOK.md` "Secret Rotation" section links to `SECRET_ROTATION.md`

**Requirements:** OPS-01, OPS-02

**Plans:**
- [ ] 01-PLAN.md — Write `scripts/smoke_all_routes.sh` + integrate into CD pipeline
- [ ] 02-PLAN.md — Write `docs/SECRET_ROTATION.md` + update `RUNBOOK.md`

**Dependencies:** Phase 04 (correlation IDs) helpful for debugging smoke test failures, but not required.

---

## Requirement Index

| ID | Phase | Description |
|----|-------|-------------|
| BAK-01 | 01 | S3 upload step in `scheduled-backup.yml` with encryption |
| BAK-02 | 01 | Backup upload failure blocks workflow (not `continue-on-error`) |
| BAK-03 | 01 | `restore_drill.sh` script + updated `BACKUP_RESTORE.md` |
| REL-01 | 02 | Redis `--maxmemory-policy noeviction` |
| REL-02 | 02 | `db-migrate` waits for `service_healthy` on postgres |
| REL-03 | 02 | Disk pressure alert in `health-monitor.yml` at 85% threshold |
| SEC-01 | 03 | All three Dockerfiles use `node:20-alpine` |
| OBS-01 | 04 | nginx injects `X-Request-ID` on all proxied requests |
| OBS-02 | 04 | `json_audit` log format includes `req_id` field |
| SEC-02 | 05 | `cms-chain` includes BasicAuth middleware |
| SEC-03 | 05 | Ollama port bound to `127.0.0.1` only |
| SEC-04 | 05 | Cosign signing is not `continue-on-error` |
| SUP-01 | 06 | All 6 infrastructure images SHA-pinned in compose |
| SUP-02 | 06 | `STRAPI_SUPER_ADMIN_PASSWORD` reads file content, not path |
| OPS-01 | 07 | `smoke_all_routes.sh` covers all 8 routing zones |
| OPS-02 | 07 | `docs/SECRET_ROTATION.md` with exact commands per secret |

---

## Execution Order

```
Phase 01 (BAK)  ──────────────────────────────────────────────────► ship
Phase 02 (REL)  ──────────────────────────────────────────────────► ship
Phase 03 (SEC)  ──────────────────────────────────────────────────► ship
Phase 04 (OBS)  ─────── depends loosely on 03 (no rebuild conflict) ► ship
Phase 05 (SEC)  ──────────────────────────────────────────────────► ship
Phase 06 (SUP)  ──────────────────────────────────────────────────► ship
Phase 07 (OPS)  ─────── benefits from 04 being done ─────────────► ship
```

Phases 01, 02, 03, 05, 06 are fully independent and can be executed in any order or in parallel across sessions.
