# CHANGELOG

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
