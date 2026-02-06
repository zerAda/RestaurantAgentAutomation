# PATCHLOG — RESTO BOT v3.2.2 (2026-01-23)

## v3.2.2 — P0 Security Hardening Release

### Tickets Implémentés

#### P0-SEC-01 — Gateway Query Token Block + Rate Limit ✅
- **Fix**: docker-compose.hostinger.prod.yml monte maintenant `nginx.conf.patched`
- **Test**: `scripts/smoke_security_gateway.sh` vérifie blocage ?token= et rate-limit
- **Rollback**: Changer le volume pour monter `nginx.conf` au lieu de `nginx.conf.patched`

#### P0-SEC-02 — Signature Meta/WhatsApp + Anti-replay ✅
- **Migration**: `db/migrations/2026-01-23_p0_sec02_meta_replay.sql`
- **Table**: `webhook_replay_guard` pour détection replay
- **Flags**: `META_SIGNATURE_REQUIRED`, `META_APP_SECRET`, `META_REPLAY_WINDOW_SEC`
- **Rollback**: `META_SIGNATURE_REQUIRED=false`

#### P0-SEC-03 — Kill-switch Legacy Shared Token ✅
- **Flag**: `LEGACY_SHARED_ALLOWED=false` (défaut)
- **Comportement**: Legacy token refusé avec 401 + event `LEGACY_TOKEN_BLOCKED`
- **Rollback**: `LEGACY_SHARED_ALLOWED=true`

#### P0-OPS-01 — Audit Trail Admin WhatsApp ✅
- **Flag**: `ADMIN_WA_AUDIT_ENABLED=true`
- **Table**: `admin_wa_audit_log` (déjà créée)
- **Rollback**: `ADMIN_WA_AUDIT_ENABLED=false`

#### P0-L10N-01 — AR-in → AR-out Garanti ✅
- **Flag**: `STRICT_AR_OUT=true` (défaut)
- **Défauts changés**: `L10N_ENABLED=true`, `L10N_STICKY_AR_ENABLED=true`
- **Rollback**: `STRICT_AR_OUT=false`

#### P0-REL-01 — Version Hygiene ✅
- **VERSION**: 3.2.2
- **Check**: integrity_gate.sh vérifie VERSION + cohérence

---

## Tickets P1 Implémentés

#### P1-FRAUD-01 — Anti-fraude (EPIC7) ✅
- **Migration**: `db/migrations/2026-01-23_p2_epic7_antifraud.sql`
- **Tables**: `fraud_rules`, extensions `conversation_quarantine`
- **Fonctions**: `apply_quarantine()`, `release_expired_quarantines()`, `fraud_eval_checkout()`, `fraud_request_confirmation()`, `fraud_confirm()`
- **Templates**: FRAUD_CONFIRM_REQUIRED, FRAUD_THROTTLED, FRAUD_QUARANTINED, FRAUD_RELEASED (FR/AR)
- **Flags**: `FRAUD_INBOUND_ENABLED`, `FRAUD_CHECKOUT_ENABLED`, `FRAUD_FLOOD_*`, `FRAUD_HIGH_ORDER_*`
- **Docs**: `docs/ANTIFRAUD.md`
- **Rollback**: `FRAUD_*_ENABLED=false`

#### P1-PAY-01 — Paiements Algérie ✅
- **Migration**: `db/migrations/2026-01-23_p1_pay01_algeria_payments.sql`
- **Tables**: `payment_intents`, `payment_history`, `customer_payment_profiles`, `restaurant_payment_config`
- **Enums**: `payment_method_enum`, `payment_status_enum`
- **Fonctions**: `calculate_deposit()`, `create_payment_intent()`, `confirm_deposit_payment()`, `collect_cod_payment()`, `update_customer_payment_profile()`
- **Templates**: PAYMENT_DEPOSIT_REQUIRED, PAYMENT_DEPOSIT_CONFIRMED, PAYMENT_COD_INFO, PAYMENT_EXPIRED, PAYMENT_BLOCKED (FR/AR)
- **Flags**: `PAYMENT_COD_ENABLED`, `PAYMENT_DEPOSIT_ENABLED`, `PAYMENT_DEPOSIT_*`, `PAYMENT_TRUST_*`
- **Docs**: `docs/PAYMENTS.md`
- **Rollback**: `PAYMENT_*_ENABLED=false`

---

## Historique v3.0 → v3.2.1

## Objectif du patch
Livrer **P0** (sécurité + déploiement + intégrité) **et** **P1 DB** (perf + rétention + contraintes d’événements) **sans aucune régression fonctionnelle**, tout en conservant la compatibilité (feature flags + migrations idempotentes).

## Résumé des changements

### DB Perf + Rétention + Contraintes événements (P1)
1) **Indexes high‑churn (lecture + purge)**
   - `inbound_messages`: ajout index `idx_inbound_messages_received_at` pour purge (l’index existant `idx_inbound_messages_window` reste inchangé).
   - `security_events`: ajout `idx_security_events_tenant_created_at` et `idx_security_events_event_type_created_at`.
   - `outbound_messages`: ajout `idx_outbound_messages_sent_at` (purge SENT par `sent_at`).
   - `workflow_errors`: ajout index `created_at` (+ `workflow_name, created_at` si colonne présente).

2) **Rétention paramétrable + audit**
   - Ajout `ops.retention_runs` (traçage) + helpers SQL :
     - `ops.purge_table_batch(...)`
     - `ops.purge_outbound_sent_batch(...)`
   - Ajout du job n8n dans `W8_OPS` : “R1 - Retention Purge (Daily 03:30)” avec mode **dry-run**.

3) **Standardisation `security_events.event_type`**
   - Ajout de `ops.security_event_types` + enum `security_event_type_enum`.
   - Valeurs seedées (compat workflows existants) : `AUTH_DENY`, `AUDIO_URL_BLOCKED`, `RETENTION_RUN`.
### Sécurité (P0)
1) **Désactivation par défaut des tokens en query string**
   - Ajout du flag `ALLOW_QUERY_TOKEN` (défaut `false`).
   - Les workflows W1/W2/W3 n’acceptent `?token=...` que si `ALLOW_QUERY_TOKEN=true`.
   - Raison : éviter fuites dans logs (Traefik / Nginx) et réduire surface replay.

2) **Normalisation des événements de sécurité**
   - Invalid token → `security_events.event_type = AUTH_DENY`
   - Audio URL bloquée → `security_events.event_type = AUDIO_URL_BLOCKED`

3) **Durcissement SSRF audioUrl** (workflow CORE)
   - Blocage **de tout IP literal** (public ou private) + IPv6 literals.
   - Maintien allowlist : `ALLOWED_AUDIO_DOMAINS`.

### Fiabilité / Déploiement (P0)
4) **Fix DB bootstrap (fresh install)**
   - `orders` est désormais créé avant `outbound_messages` (FK dependency), évite un échec sur Postgres init.

5) **Dev compose assaini**
   - Suppression des placeholders `CHANGE_ME`.
   - Pin version n8n (`N8N_VERSION`, défaut 1.80.0) pour réduire l’aléatoire.
   - Ajout de `ALLOW_QUERY_TOKEN` et `ALLOWED_AUDIO_DOMAINS`.

### QA / Tooling (P0)
### EPIC3 — Tracking (P2)- DB:  +  + trigger enqueue WhatsApp (idempotent + anti-spam)- Templates: - Admin endpoint:  ()
6) **Smoke tests corrigés** (`scripts/smoke.sh`)
   - Vérifie healthz, inbound valid, invalid token → log `AUTH_DENY`, audio SSRF → log `AUDIO_URL_BLOCKED`.

7) **Integrity Gate ajouté** (`scripts/integrity_gate.sh`)
   - `bash -n`, scan placeholders, validation JSON workflows, check ordering DB, parse YAML best-effort.

### Documentation
8) Docs mises à jour
   - `README.md`, `docs/API_CONVENTIONS.md`, `docs/LAST_VERIFICATION_REPORT.md`, `tests/tests.md`.

---

## Addendum SYSTEM-3 (OPS/SEC/QA) — 2026-01-22

### Ops — Backup/Restore (P1-OPS-002)
- Ajout scripts :
  - `scripts/backup_postgres.sh` : `pg_dump -Fc` (format custom) + rotation `RETENTION_DAYS` + checksum sha256.
  - `scripts/restore_postgres.sh` : restore `pg_restore` avec options `--clean` et `--if-exists` + garde-fou `CONFIRM_RESTORE=YES`.
  - `scripts/backup_redis.sh` : archive volume Redis `/data` + rotation (si Redis persistant).
- Ajout docs :
  - `docs/BACKUP_RESTORE.md` (playbook exécutable + restore drill mensuel)
  - `docs/RUNBOOKS.md` (routines Ops/Sec/QA)

### Sécurité — Scopes + RBAC (P1-SEC-003)
- Modèle scopes par client : `api_clients.scopes` (jsonb array)
- Enforcement :
  - `/v1/admin/*` → exige `admin:*` ou `admin:read|admin:write`
  - endpoints partenaires → scopes dédiés (si activés)
- Refus de scope : log `security_events.event_type = 'SCOPE_DENY'`.
- Ajout workflow démonstrateur admin : `workflows/W9_ADMIN_PING.json`.

---

## Addendum EPIC2 (Livraison) — 2026-01-22

### DEL-001 — Zones + Quote
- Migration DB : `db/migrations/2026-01-22_p2_epic2_delivery.sql`
- Seed demo : `db/seed_delivery_demo.sql` (replay-safe)
- Endpoint quote : `POST /v1/customer/delivery/quote` (workflow `W10_CUSTOMER_DELIVERY_QUOTE.json`)
- Endpoint admin zones (CRUD minimal) : `GET/POST /v1/admin/delivery/zones` (workflow `W11_ADMIN_DELIVERY_ZONES.json`)

### DEL-002 — Clarification d’adresse
- Table `address_clarification_requests` + templates FR/AR/Darja (`templates/delivery/*`)
- Messages d’erreur explicites : `DELIVERY_ZONE_NOT_FOUND`, `DELIVERY_ZONE_INACTIVE`, `DELIVERY_MIN_ORDER`

### DEL-003 — Créneaux
- Tables `delivery_time_slots` + `delivery_slot_reservations`
- Quote peut retourner des slots (si `DELIVERY_SLOTS_ENABLED=true`)

### Gateway
- Nouveau namespace : `/v1/customer/*` (nginx prod/test)

### QA
### EPIC3 — Tracking (P2)- DB:  +  + trigger enqueue WhatsApp (idempotent + anti-spam)- Templates: - Admin endpoint:  ()
- Fixtures ajoutées : `tests/fixtures/20_seed_delivery_demo.sql` + client `test-token-customer`
- `scripts/test_harness.sh` étendu (quote + admin zones)
- `scripts/integrity_gate.sh` étendu (livrables EPIC2)

### QA/CI — Test harness (P1-QA-002)
### EPIC3 — Tracking (P2)- DB:  +  + trigger enqueue WhatsApp (idempotent + anti-spam)- Templates: - Admin endpoint:  ()
- Ajout stack de test : `docker/docker-compose.test.yml` + gateway test (`infra/gateway/nginx.test.conf`).
- Fixtures DB : `tests/fixtures/*.sql` (tenant + api_clients + sample).
- Script 1-commande : `scripts/test_harness.sh` (migrations + seed + import + smoke + teardown).
- Integrity Gate renforcé : vérifie présence livrables SYSTEM-3 + gating scopes sur workflows.

## Fichiers principaux modifiés
- `workflows/W1_IN_WA.json`
- `workflows/W2_IN_IG.json`
- `workflows/W3_IN_MSG.json`
- `workflows/W4_CORE.json`
- `db/bootstrap.sql`
- `config/.env.example`
- `docker/docker-compose.yml`
- `scripts/smoke.sh`
- `scripts/integrity_gate.sh`
- `docs/*`

## Compatibilité
- Compat **legacy** `?token=` conservée mais **désactivée** (opt-in via `ALLOW_QUERY_TOKEN=true`).
- Pas de breaking change DB : uniquement correction d’ordre dans `bootstrap.sql` (impact fresh install) + migrations existantes.

---

## EPIC5 — Localisation (P2)

### L10N-001 — FR/AR script-first + Darija intents
- CORE : `workflows/W4_CORE.json` (détection script arabe, darija translit `menu`/`checkout`, stabilité boutons via `state.lastResponseLocale`).
- Flags : `L10N_ENABLED`, `L10N_STICKY_AR_ENABLED`, `L10N_STICKY_AR_THRESHOLD`.

### L10N-002 — Préférence persistée (LANG) + tracking
- DB : `db/migrations/2026-01-23_p2_epic5_l10n.sql`
  - `message_templates`, `customer_preferences`, `normalize_locale()`
  - templates `_GLOBAL` (CORE + WA_ORDER_STATUS_*)
  - `wa_order_status_text()` + `build_wa_order_status_payload()` (utilise `customer_preferences`).

### L10N-003 — Pilotage admin templates sur WhatsApp
- Admin console : `workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json`
  - `!template get|set|vars <KEY> [fr|ar] ...` (RBAC admin/owner, écritures tenant-only).

### Docs & QA
- Docs : `docs/L10N.md`, `docs/EPIC5_ACCEPTANCE_CRITERIA.md`, `docs/ROLLBACK_EPIC5_L10N.md`, `docs/RELEASE_PLAN_EPIC5.md`, `docs/TEMPLATE_CATALOG.md`, `docs/L10N_ADMIN_WA_COMMANDS.md`.
- Tests : `scripts/test_l10n_script_detection.py`, `scripts/test_template_render.py`, `scripts/test_darja_intents.py`, datasets `tests/arabic_script_cases.json`, `tests/template_render_cases.json`.
- Fixtures : `tests/fixtures/45_seed_l10n_demo.sql`.

---

## EPIC6 — Support (P2)

### SUP-001 — Handoff humain (agent)
- DB : ajout `support_tickets`, `support_assignments`, `support_ticket_messages` + indexes.
- CORE : trigger handoff par `HELP`/`AIDE`/`AGENT`/`SUPPORT` + fallback FAQ (si activée) + ack client.
- Admin : **pilotage via WhatsApp** (pas de nouvelle UI) avec console `!tickets`, `!take`, `!reply`, `!close`.

### SUP-002 — FAQ (RAG light)
- DB : `faq_entries` + tsvector + index GIN.
- Fixtures : seed FAQ FR/AR.

### Workflows / Flags
- W1 : routage des messages commençant par `!` vers W14 (si `ADMIN_WA_CONSOLE_ENABLED=true`).
- W14 : console admin WhatsApp (RBAC via `restaurant_users`).
- Flags : `SUPPORT_ENABLED`, `FAQ_ENABLED`, `ADMIN_WA_CONSOLE_ENABLED`, `ADMIN_WA_CONSOLE_WORKFLOW_ID`.

### QA
- Test harness étendu : FAQ répond sans ticket, HELP crée un ticket, commande admin ne crée pas de ticket.
- Integrity Gate étendu : présence livrables EPIC6.

---

---

## P0 SECURITY PATCH AGENTS — 2026-01-23

### Context
Based on the comprehensive Ralphe audit report (health score: 68/100, verdict: GO-WITH-CONDITIONS), a set of patch agents was created to address critical security and UX issues before production deployment.

### Agents Created

| Agent | ID | Priority | Description |
|-------|-----|----------|-------------|
| AGENT_01 | P0-SEC-01 | CRITICAL | Gateway query token blocking |
| AGENT_02 | P0-SEC-02 | CRITICAL | Disable legacy shared token |
| AGENT_03 | P0-SEC-03 | HIGH | Provider signature validation |
| AGENT_04 | P0-SUP-01 | HIGH | Admin WhatsApp audit log |
| AGENT_05 | P0-L10N-01 | HIGH | Enable L10N by default |
| AGENT_06 | P0-OPS-01 | HIGH | SLO alerting & monitoring |
| AGENT_07 | P0-PERF-01 | MEDIUM | Database performance indexes |
| AGENT_08 | P0-QA-01 | HIGH | Security smoke tests |
| AGENT_10 | - | - | Patch orchestration (master plan) |
| AGENT_11 | - | - | Go/No-Go checklist validator |

### Files Created

#### Agent Documentation
- `agents/README.md` - Overview and quick start
- `agents/AGENT_01_SECURITY_GATEWAY.md`
- `agents/AGENT_02_DISABLE_LEGACY_TOKEN.md`
- `agents/AGENT_03_SIGNATURE_VALIDATION.md`
- `agents/AGENT_04_ADMIN_WA_AUDIT.md`
- `agents/AGENT_05_L10N_ENABLE.md`
- `agents/AGENT_06_SLO_ALERTING.md`
- `agents/AGENT_07_PERFORMANCE_INDEXES.md`
- `agents/AGENT_08_SMOKE_TESTS_SECURITY.md`
- `agents/AGENT_10_ORCHESTRATOR.md`
- `agents/AGENT_11_GO_NO_GO_VALIDATOR.md`

#### Configuration Patches
- `config/.env.example.patched` - Updated with all P0 security settings

#### Infrastructure Patches
- `infra/gateway/nginx.conf.patched` - Gateway with query token blocking + rate limiting

#### Database Migrations
- `db/migrations/2026-01-23_p0_sec02_disable_legacy_token.sql` - Token migration tracking
- `db/migrations/2026-01-23_p0_sup01_admin_wa_audit.sql` - Admin WA audit log table
- `db/migrations/2026-01-23_p0_perf_indexes.sql` - Performance optimization indexes

#### Scripts
- `scripts/apply_p0_patches.sh` - Automated patch application
- `scripts/smoke_security.sh` - Security smoke tests

### Key Security Changes

1. **P0-SEC-01**: Gateway now blocks `?token=` and `?access_token=` query parameters
2. **P0-SEC-02**: Legacy shared token disabled by default (`LEGACY_SHARED_TOKEN_ENABLED=false`)
3. **P0-SEC-03**: Provider signature validation framework (warn mode → enforce)
4. **P0-SEC-05**: Rate limiting at gateway level (IP + token)

### Key Configuration Changes

```env
# Security (CRITICAL)
LEGACY_SHARED_TOKEN_ENABLED=false
WEBHOOK_SHARED_TOKEN=
SIGNATURE_VALIDATION_MODE=warn

# Localization (required for Algeria)
L10N_ENABLED=true
L10N_STICKY_AR_ENABLED=true

# Audit (compliance)
ADMIN_WA_AUDIT_ENABLED=true

# Alerting (operations)
ALERT_WEBHOOK_URL=
ALERT_OUTBOX_PENDING_AGE_SEC=60
ALERT_DLQ_COUNT=10
```

### Deployment Instructions

```bash
# 1. Apply patches
chmod +x scripts/apply_p0_patches.sh
./scripts/apply_p0_patches.sh

# 2. Apply database migrations
psql -f db/migrations/2026-01-23_p0_sec02_disable_legacy_token.sql
psql -f db/migrations/2026-01-23_p0_sup01_admin_wa_audit.sql
psql -f db/migrations/2026-01-23_p0_perf_indexes.sql

# 3. Update production .env
# Copy settings from config/.env.example.patched

# 4. Validate
./scripts/smoke_security.sh
```

### Rollback

See individual agent files for specific rollback instructions. Quick rollback:
- Set `LEGACY_SHARED_TOKEN_ENABLED=true` temporarily
- Restore `nginx.conf` from backup
- Migrations are additive and safe to keep

---

## NO DEBT / NO REGRESSION CLAUSE
- ✅ Tout changement est **patché dans le repo** (SQL migrations, workflow JSON, scripts, docs).
- ✅ Tout changement a un **plan de test** (Integrity Gate + runbook runtime) et doit être validé avant Go-Live.
- ✅ Tout changement est **documenté** (`docs/*`, `CHANGELOG.md`).
- ✅ Rollback disponible (`ROLLBACK.md`).
- ✅ **P0 Security Agents** créés avec documentation complète et scripts d'application.




## v3.2.3 (2026-01-23)
- P0-OPS-01: W8 SLO alerts now sent to ALERT_WEBHOOK_URL with cooldown (ops_kv).
- P0-OPS-02: Added incident and ops routines playbooks.
- P0-OPS-03: Added idempotency headers and duplicate handling for outbox sends.
- Meta webhook verify workflow added; W1 inbound signature + legacy kill switch enforced by flags.
- Cleanup: removed *.patched source-of-truth duplication; updated integrity gate accordingly.

## Phase 6 — Diamond Driver WhatsApp (2026-02-05)

### P0-D6-01 — Strapi Models

- **Modified**: `driver` schema — enum uppercase (INVITED/ACTIVE/SUSPENDED), removed broken `restaurant` relation, replaced `current_order` with `assigned_orders` (oneToMany), added `last_seen_at`
- **Modified**: `order` schema — added `delivery_status` enum (READY_FOR_DELIVERY/OUT_FOR_DELIVERY/DELIVERED), `driver` relation (manyToOne), `otp_hash`, `otp_expires_at`, `otp_attempts`, `delivered_at`, `delivery_commune`, `delivery_wilaya`, `delivery_address`
- **Created**: `driver-order-ignore` collection (driver_phone + order + ignored_at)

### P0-D6-02 — W_DRIVER_ONBOARDING

- Added `is_active` gate (inactive drivers skipped)
- Enum value updated: `invited` → `INVITED`
- Button ID changed to `MENU` for dashboard entry

### P0-D6-03 — W_DRIVER_ROUTER

- Full rewrite: anti-spam validation, `is_active` filter on driver lookup, `last_seen_at` update
- Buttons renamed: `📦 Livrables` / `🚚 En cours` / `🕘 Historique`
- Added "Not Registered" message for unknown phones

### P0-D6-04 — W_DRIVER_AVAILABLE_LIST

- Renamed from `W_DRIVER_AVAILABLE_ORDERS`
- Ignore filter via `driver-order-ignores` query
- 1 order = 1 WhatsApp message (SplitInBatches)
- Per-card buttons: `✅ Prendre` / `🙈 Ignorer` (max 2, within WA 3-button limit)
- Footer message with `🔄 Actualiser` / `📋 Menu`

### P0-D6-05 — W_DRIVER_ACTIONS + OTP Verify + History

- **Actions**: Full rewrite with Switch node routing (claim/ignore/delivered_prompt/fallback)
- **Claim**: Race condition protection (re-fetch + status check), OTP hashed SHA-256, expiry 30min, auto-activate INVITED → ACTIVE on first claim
- **Ignore**: Creates `driver-order-ignore` record, sends confirmation
- **OTP Verify**: Hash-based verification (never queries plaintext OTP), max 3 attempts, expiry check, per-attempt feedback
- **History**: Updated query to use `delivery_status` + `driver` relation instead of `driver_phone` string

### P0-D6-06 — Config + Tests

- Added env vars: `DRIVER_ENABLED`, `DRIVER_OTP_EXPIRY_MINUTES`, `DRIVER_OTP_MAX_ATTEMPTS`, `DRIVER_ANTI_SPAM_MS`
- Created `scripts/smoke/test_driver_phase6.sh` (webhook + Strapi + JSON validation tests)

### Security Notes

- OTP stored as SHA-256 hash only — plaintext never persisted
- OTP expires after configurable window (default 30min)
- Max 3 OTP attempts before lockout
- Race condition on claim prevented by re-fetch + status validation
- Driver must be `is_active=true` to use any endpoint
- All Strapi calls use Bearer token auth
