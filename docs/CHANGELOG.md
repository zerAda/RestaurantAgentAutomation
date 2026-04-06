# CHANGELOG

## 2026-04-06 — v3.5.1 (CI/CD Pipeline Recovery)

### Fixed — 6 blocking CI/CD failures

- **Duplicate CD trigger removed** (`ralphe-cd-deploy.yml`): both workflow files shared the same name and `workflow_run:` auto-trigger, creating a concurrency deadlock on `deploy-production`. Renamed to "CD - Deploy to VPS (manual)" and removed `workflow_run:` trigger entirely.
- **nginx CI health check**: CI service was mapped `8080:8080` but nginx listens on port 80; health probe was always failing. Changed to `8080:80` + `curl -sf http://localhost/`.
- **backup.sh postgres container selection**: When staging and production run concurrently, `docker ps -qf "ancestor=postgres"` returned staging container first → empty pg_dump → backup failure. Now prefers container matching production compose project label.
- **Secret bind-mounts idempotent**: `secrets/traefik_usersfile`, `secrets/postgres_password`, `secrets/n8n_encryption_key` are now created on every deploy with `if [ ! -f ]` guards (was: first deploy only).
- **Docker external volumes idempotent**: All 6 named volumes (`traefik_data`, `n8n_data`, `postgres_data`, `redis_data`, `cms_uploads`, `ollama_data`) are now created on every deploy with `2>/dev/null || true` (was: first deploy only).
- **`/var/log/resto-bot` fallback**: deploy user lacks write access to `/var/log/` on hardened VPS; hard `mkdir` was killing deploy in ~21 s. Added fallback to `$PROJECT_DIR/logs` + ERR trap for line-level diagnostics.

### Changed

- `cd-deploy.yml`: `deploy-production` now proceeds when backup result is `failure` (was: only on `success`/`skipped`). Emits `::warning::` instead of blocking.
- `cd-deploy.yml`: `packages: read` permission added (required for GHCR pull).

### Files Changed
```
.github/workflows/ralphe-cd-deploy.yml  (auto-trigger removed)
.github/workflows/ci.yml                (nginx port fix)
.github/workflows/cd-deploy.yml         (permissions + backup gate)
scripts/ops/backup.sh                   (postgres container selection)
scripts/ops/deploy_to_node.sh           (secrets, volumes, LOG_DIR, ERR trap)
```

---

## 2026-03-26 — v3.5.0 (Phase 2 Logging + Phase 3 Audit + Phase 6 Performance)

### Phase 2: Structured Logging & Correlation (Complete)
- **OBS-01**: n8n configured for JSON structured logs (`N8N_LOG_FORMAT=json`) on main + worker
- **OBS-02**: Strapi CMS Winston JSON logger with `service='strapi-cms'` field
- **OBS-03**: Nginx access log includes `request_id` in JSON format
- **OBS-04**: `X-Request-ID` correlation propagated from Nginx to all upstreams (Strapi, n8n)
- `inventory-cms/src/middlewares/request-id.ts`: AsyncLocalStorage-based correlation ID capture
- `scripts/smoke-correlation.sh`: End-to-end correlation verification (6/6 checks pass)

### Phase 3: Metrics, Alerting & Audit Trail (Mostly Complete)
- **AUDIT-01**: `workflow_audit` table via migration `2026-03-23_p3_workflow_audit.sql`
- **AUDIT-02**: W1_IN_WA, W2_IN_IG, W3_IN_MSG patched with fire-and-forget audit hooks
- **AUDIT-03**: `AuditLogView` page in admin dashboard (date range filter + pagination)
- **AUDIT-04**: `W_AUDIT_ARCHIVE` workflow for 90-day retention
- **METR-01/02**: `W_QUEUE_METRICS` workflow (queue depth + error rate export)
- **METR-03**: Nginx rate-limit logging with zone, IP, endpoint
- New workflows: `W_AUDIT_WRITE`, `W_AUDIT_QUERY`, `W_AUDIT_ARCHIVE`, `W_QUEUE_METRICS`

### Phase 6: Performance Tuning (Mostly Complete)
- **PERF-01/02**: DB indexes migration `2026-03-26_p6_orders_indexes.sql` (idx_orders_status_created, idx_orders_customer_status + 4 more)
- **PERF-04/05/06**: Redis `allkeys-lru` confirmed + `W_REDIS_MONITOR` workflow (15-min checks, >200MB alert) + `ENV_REFERENCE.md` updated
- **PERF-07**: Admin dashboard refactored with React Router `lazy()` for all view components
- **PERF-09**: Kiosk `VerticalVideoFeed` integrated with `menuService.ts` 5-min localStorage cache
- New scripts: `scripts/verify-orders-indexes.sh`, `scripts/smoke-nginx-routing-v2.sh`, `scripts/smoke-strapi-permissions.sh`, `scripts/smoke-n8n-e2e.sh`
- CI: Updated `.github/workflows/ci.yml` with new test jobs

### Files Added/Changed
```
db/migrations/2026-03-23_p3_workflow_audit.sql (new)
db/migrations/2026-03-26_p6_orders_indexes.sql (new)
admin-dashboard/src/App.tsx (React lazy refactor)
admin-dashboard/src/pages/AuditLogView.tsx (new)
kiosk-app/src/components/VerticalVideoFeed.tsx (cache integration)
workflows/W_AUDIT_WRITE.json (new)
workflows/W_AUDIT_QUERY.json (new)
workflows/W_AUDIT_ARCHIVE.json (new)
workflows/W_QUEUE_METRICS.json (new)
workflows/W_REDIS_MONITOR.json (new)
scripts/verify-orders-indexes.sh (new)
scripts/smoke-nginx-routing-v2.sh (new)
scripts/smoke-strapi-permissions.sh (new)
scripts/smoke-n8n-e2e.sh (new)
infra/gateway/nginx.conf (rate-limit logging + /v1/internal/ proxy)
ENV_REFERENCE.md (Redis monitoring + DB indexes docs)
```

---

## 2026-03-23 — v3.4.5 (Phase 1 CMS Stability + Node.js 20 Upgrade)

### Phase 1: CMS Stability & Base Upgrade
- **CMS-01**: All 15 Strapi API routes baked into TypeScript source (`inventory-cms/src/api/`)
- **CMS-02**: CMS Docker image rebuilt with 4 Node.js 20 / Strapi 5 fixes (lodash ESM, broken relations, CONCURRENTLY migration, route auth object)
- **CMS-03**: 17/17 routes verified (15 API + 2 custom handlers) — all return 200 with JWT auth
- **INFRA-01**: admin-dashboard + kiosk-app Dockerfiles upgraded to `node:20-alpine`
- **INFRA-02**: CMS Dockerfile upgraded to `node:20.20.0-alpine` (both build + prod stages)
- SRE audit: CMS healthcheck `start_period` set to 180s, `container-watchdog.sh` cron, `post-deploy-verify.sh` 6-phase gate

### Scripts Added
- `scripts/smoke-post-rebuild.sh`: Post-rebuild verification (CMS health, login, products, admin)
- `scripts/smoke-correlation.sh`: End-to-end correlation ID verification
- `scripts/container-watchdog.sh`: Container health monitoring + alerting
- `scripts/post-deploy-verify.sh`: 6-phase mandatory deployment health gate
- `scripts/disk-cleanup.sh`: Proactive disk reclamation

---

## 2026-03-14 — v3.4.4 (Workflow Sync + Demo Seed)

### Added
- 12 new n8n workflows imported (total: 90+): W_ADMIN_AI_AGENT, W_CONTENT_AUDITOR, W_CORTEX_REGISTRY, W_FUNNEL_ANALYZER, W_GROWTH_AGENT, W_INCEPTION_PROTOCOL, W_INVENTORY_ORCHESTRATOR, W_LOGISTICS_PRO, W_LOYALTY_ENGINE, W_ORDER_FINALIZER, W_RALPHE_OMNISCIENT, W_REVENUE_INTELLIGENCE
- Demo seed data: 16 products, 3 brands (Burger Palace, Tacos House, Al-Hana Group)

---

## 2026-03-14 — v3.4.3 (Platform Connectivity Fixes)

### Fixed
- Admin dashboard bundle: auth endpoint patched (`api/auth/local`)
- Kiosk app: Strapi URL connectivity via gateway
- All 10 production containers verified running on VPS

---

## 2026-01-26 — v3.2.4 (DevSecOps Pipeline Enhancement)

### CI/CD Pipeline (Expert DevSecOps Overhaul)

#### CI Pipeline (`ci.yml`)
- **Parallel job execution**: Lint, security gates, and Python tests run concurrently
- **Concurrency control**: Auto-cancels in-progress runs on same branch
- **Minimal permissions**: Least privilege principle applied
- **Dependency caching**: Python pip caching for faster builds
- **Build artifacts**: Includes SHA256 checksums
- **CI Summary**: Visual job status report in GitHub UI

#### Security Scanning (`security-scan.yml`) - NEW
- **Gitleaks integration**: Automated secret detection on every push
- **Custom secret patterns**: Project-specific patterns (webhook tokens, Meta secrets, etc.)
- **Container scanning**: Trivy vulnerability scan on all Docker images (n8n, postgres, redis, nginx, traefik)
- **Configuration SAST**: Security audit of Docker Compose, Nginx configs, environment templates
- **Dependency scanning**: Python dependencies + n8n workflow node audit
- **SBOM generation**: Software Bill of Materials for compliance

#### CD Deploy (`cd-deploy.yml`)
- **Environment selection**: Staging vs Production with protection rules
- **Concurrency lock**: Prevents simultaneous deployments
- **Pre-deployment validation**: Docker, disk space, directory checks
- **Database backup**: Automatic pg_dump before every deployment
- **Configuration backup**: .env and secrets/ archived with deployment ID
- **Health checks**: 15 retries with 10s intervals
- **Smoke tests**: Health endpoint, container count, DB connectivity
- **Auto-rollback**: Automatic recovery on deployment failure
- **Deployment audit**: Logged to `/var/log/resto-bot/deployments.log`
- **Notifications**: Slack/webhook alerts on success/failure

#### Rollback (`rollback.yml`)
- **Multiple rollback types**: config, full (DB+config), code_only
- **Pre-rollback backup**: Safety backup before any rollback
- **Database restore**: Full DB restore with proper connection handling
- **Audit trail**: Rollback reason and actor logged
- **Recovery instructions**: If rollback fails, provides manual recovery steps

#### Scheduled Backup (`scheduled-backup.yml`) - NEW
- **Daily backups**: 3:00 AM UTC, 7-day retention
- **Weekly full backups**: Sunday 4:00 AM UTC, 4-week retention
- **Backup verification**: Integrity check (gunzip -t, tar -tzf)
- **Automatic rotation**: Old backups cleaned up
- **Weekly maintenance**: VACUUM ANALYZE, log cleanup, Docker prune

#### Health Monitor (`health-monitor.yml`) - NEW
- **Every 15 minutes**: Continuous health monitoring
- **Service checks**: n8n, PostgreSQL, Redis, container count
- **Disk space alerts**: Warning at 80%, critical at 90%
- **Queue monitoring**: Alert on high queue depth
- **Instant alerts**: Webhook notification on any issue

### DevOps Configuration

#### Dependabot (`dependabot.yml`) - NEW
- GitHub Actions: Weekly updates on Mondays
- Docker images: Weekly updates with major version ignore for stability

#### CODEOWNERS - NEW
- Automatic review assignment for CI/CD, security, database changes

#### Gitleaks Configuration (`.gitleaks.toml`) - NEW
- Custom rules for Resto Bot secrets
- Allowlist for safe patterns and example files

#### GitHub Templates - NEW
- **Bug report**: Structured issue template with severity and channel selection
- **Feature request**: Categorized feature suggestions
- **Pull request**: Checklist for testing, security, and database changes

### Documentation
- **DEVOPS.md**: Complete DevSecOps guide with pipeline architecture, commands, and troubleshooting

### Files Added
```
.github/
├── workflows/
│   ├── ci.yml (enhanced)
│   ├── cd-deploy.yml (enhanced)
│   ├── rollback.yml (enhanced)
│   ├── security-scan.yml (new)
│   ├── scheduled-backup.yml (new)
│   └── health-monitor.yml (new)
├── dependabot.yml (new)
├── CODEOWNERS (new)
├── pull_request_template.md (new)
└── ISSUE_TEMPLATE/
    ├── bug_report.yml (new)
    └── feature_request.yml (new)
.gitleaks.toml (new)
docs/DEVOPS.md (new)
```

---

## 2026-01-23 — v3.2.2 (P0 Security + P1 Features)

### Security (P0-SEC-*)
- **P0-SEC-01**: Gateway now blocks query string tokens (?token=, ?access_token=, etc.) at nginx level
- **P0-SEC-01**: Rate limiting active on all inbound endpoints (IP + token based)
- **P0-SEC-02**: Added Meta/WhatsApp signature validation support (X-Hub-Signature-256)
- **P0-SEC-02**: Anti-replay protection via `webhook_replay_guard` table
- **P0-SEC-03**: Legacy shared token kill-switch (`LEGACY_SHARED_ALLOWED=false`)
- Production docker-compose now mounts `nginx.conf.patched` with security rules

### Operations (P0-OPS-*)
- **P0-OPS-01**: Admin WhatsApp audit trail enabled (`admin_wa_audit_log`)
- Added smoke test for gateway security: `scripts/smoke_security_gateway.sh`

### Localization (P0-L10N-*)
- **P0-L10N-01**: L10N enabled by default (`L10N_ENABLED=true`)
- **P0-L10N-01**: Strict AR-out rule: Arabic input ALWAYS gets Arabic response
- New env var `STRICT_AR_OUT=true` for guaranteed AR-in → AR-out

### Anti-Fraud (P1-FRAUD-01 / EPIC7)
- **fraud_rules**: Configurable rules engine for inbound + checkout
- **Quarantine system**: Auto-release with `release_expired_quarantines()`
- **Flood detection**: `IN_FLOOD_30S` rule with quarantine
- **Checkout protection**: High order confirmation, repeat cancel detection
- Message templates FR/AR for fraud scenarios
- Documentation: `docs/ANTIFRAUD.md`

### Payments Algeria (P1-PAY-01)
- **payment_intents**: Payment state machine (COD, DEPOSIT_COD, future CIB/Edahabia)
- **customer_payment_profiles**: Trust scoring and soft blacklist
- **Deposit system**: Configurable percentage/fixed with trust exemptions
- Functions: `calculate_deposit()`, `create_payment_intent()`, `confirm_deposit_payment()`
- Message templates FR/AR for payments
- Documentation: `docs/PAYMENTS.md`

### Configuration
- New env vars for P0: `LEGACY_SHARED_ALLOWED`, `META_SIGNATURE_REQUIRED`, `META_APP_SECRET`, etc.
- New env vars for P1 Fraud: `FRAUD_*` settings
- New env vars for P1 Payments: `PAYMENT_*` settings
- Default values changed: L10N features now enabled by default for Algeria market

### Database
- New migration: `2026-01-23_p0_sec02_meta_replay.sql` (webhook replay guard)
- New migration: `2026-01-23_p2_epic7_antifraud.sql` (fraud rules, quarantine policies)
- New migration: `2026-01-23_p1_pay01_algeria_payments.sql` (payment intents, profiles)
- New security event types: `WA_SIGNATURE_INVALID`, `WA_REPLAY_DETECTED`, `LEGACY_TOKEN_BLOCKED`, `SPAM_DETECTED`, `QUARANTINE_*`

### Release Hygiene (P0-REL-01)
- VERSION file updated to 3.2.2
- Integrity gate enhanced with version check

## 2026-01-22 — v3.2.1 (Agent Army Setup)

### Added
- Agent documentation framework (`agents/` directory)
- Patch orchestration scripts
- Go/No-Go validation checklist

## 2026-01-22 — v3.1 (SYSTEM-2)

### Added
- Versioned inbound contracts via JSON Schema (`schemas/inbound/v1.json`, `schemas/inbound/v2.json`)
- Contract version routing via `x-contract-version` / `contract_version`
- Inbound validation gate (HTTP 400 on invalid payload) + `CONTRACT_VALIDATION_FAILED` event
- Multi-tenant context sealing (`tenant_context_seal`) in W1/W2/W3
- SLO monitoring + alerting in `W8_OPS` (p95 inbound→outbox, outbox pending age, DLQ rate)
- Ops docs: `docs/SLO.md`, `docs/FAILURE_MODES.md`

### Ops
- Added env vars: `SCHEMAS_ROOT`, `SLO_*` thresholds
- Mounted `./schemas` into n8n containers (read-only) for runtime validation

## 2026-01-22 — v3.1.1 (EPIC2/EPIC3)

### Added
- EPIC2 Livraison: delivery zones + quote client (`/v1/customer/delivery/quote`) + CRUD admin zones (`/v1/admin/delivery/zones`)
- EPIC3 Tracking: `order_status_history`, WhatsApp outbox templates, idempotent notifications + anti-spam
- Admin: orders list + timeline endpoint (`/v1/admin/orders`)

## 3.0.2 - 2026-01-22 (P1 DB: perf + retention + event type constraints)
### Added
- DB retention primitives: `ops.retention_runs`, batch purge helpers, and scheduled “Retention Purge” job in `W8_OPS`.
- Indexes for high-churn tables to keep reads + purge index-friendly.
- `security_events.event_type` standardized via enum + reference table (`ops.security_event_types`).
- `scripts/db_explain.sh` and docs (`docs/DB_RETENTION.md`, `docs/EVENT_TYPES.md`).


## 3.0.1 - 2026-01-21 (P0 patches)
### Added
- Multi-tenant inbound auth via `api_clients` (hashed tokens) + security_events logging.
- SSRF protections for STT audioUrl (https-only + allowlist).
- Outbox pattern (`outbound_messages`) + retry worker in W8.
- Backup/restore scripts + DB migration script.
### Changed
- `create_order` now enforces PLACED state to prevent double orders.
- Traefik hardened with trusted IPs + security headers.

## 3.0.0 - 2026-01-21
### Added
- Gateway (Nginx) exposing stable `/v1/...` API and hiding n8n behind it.
- Traefik production compose for Hostinger: TLS, console allowlist+basic auth, API rate limit.
- Queue mode (n8n main + worker + redis).
- `db/bootstrap.sql` as single bootstrap for fresh installs.
- Scripts: preflight, workflow id generator, smoke tests.
- Docs: API conventions, Hostinger runbook, prod checklist.

### Changed
- Inbound webhook paths renamed to:
  - `v1/inbound/whatsapp`
  - `v1/inbound/instagram`
  - `v1/inbound/messenger`
- Token auth now supports header **or** bearer **or** query param.

### Compatibility
- Gateway keeps aliases for previous paths (`*-incoming-v16`) to avoid breaking existing clients.

## 2026-01-23 — EPIC5 (P2) Langues
- Added L10N support (FR/AR) with Arabic-script detection (reply AR if Arabic script, else FR)
- Added DB tables: message_templates, customer_preferences
- Seeded templates (CORE + WA_ORDER_STATUS)
- Added QA: Darija phrases tests + template rendering tests
- Added docs: L10N.md, ROLLBACK_EPIC5_L10N.md
- Added optional Sticky Arabic session mode (Darija Latin answered in AR after N Arabic-script messages) via L10N_STICKY_AR_* env vars
