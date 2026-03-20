# Backlog JIRA-ready — RESTO BOT v3.0

> Format : **Title, Priority, Status, Description, Scope, Steps, Expected/Actual, Impact, AC/DoD, Test Plan, Rollback, Estimation, Dependencies**

---

## EPIC 0 — Prod Stabilization

### P0-DB-001 — Fix fresh install DB init (bootstrap ordering + idempotency)
- **Priority**: P0
- **Status**: ✅ DONE (patch 2026-01-22)
- **Description**: Fresh install Postgres échouait car `outbound_messages` avait une FK vers `orders` avant création de `orders`.
- **Scope**: `db/bootstrap.sql`
- **Steps**:
  1. Fresh Postgres volume
  2. Init via `db/bootstrap.sql`
- **Expected**: Init réussie (aucune erreur FK)
- **Actual (avant)**: Erreur "relation \"orders\" does not exist" lors de `CREATE TABLE outbound_messages`
- **Impact**: Bloquant déploiement from scratch
- **AC/DoD**:
  - `orders` créé avant `outbound_messages`
  - Integrity Gate vérifie l’ordre
- **Test Plan**:
  - `./scripts/integrity_gate.sh` (check ordering)
  - Fresh install (à exécuter en environnement cible)
- **Rollback**: Aucun (bootstrap uniquement)
- **Estimation**: S
- **Dependencies**: None

### P0-QA-001 — Smoke tests end-to-end (token invalid, SSRF audioUrl, idempotency)
- **Priority**: P0
- **Status**: ✅ DONE (patch 2026-01-22)
- **Description**: Smoke script contenait une erreur de quoting et des assertions inversées.
- **Scope**: `scripts/smoke.sh`, `tests/tests.md`
- **Steps**:
  1. Exécuter `./scripts/smoke.sh`
- **Expected**:
  - healthz OK
  - inbound valid token OK
  - invalid token → `security_events` contient `AUTH_DENY`
  - audio url interdite → `security_events` contient `AUDIO_URL_BLOCKED`
- **Actual (avant)**:
  - Check DB cassé (quotes)
  - Message d’erreur "invalid token accepted" incohérent
- **Impact**: Pas de gate fiable
- **AC/DoD**:
  - Script exécutable sans erreur bash
  - Assertions alignées sur exigences P0
- **Test Plan**:
  - `bash -n scripts/smoke.sh`
  - Exécution en prod/stage
- **Rollback**: restaurer script précédent
- **Estimation**: S
- **Dependencies**: P0-SEC-001

### P0-SEC-001 — Harden inbound auth + reduce token leakage
- **Priority**: P0
- **Status**: ✅ DONE (patch 2026-01-22)
- **Description**: Les tokens en query string fuient dans les logs et augmentent le risque de replay.
- **Scope**: `workflows/W1_IN_WA.json`, `W2_IN_IG.json`, `W3_IN_MSG.json`, `docs/API_CONVENTIONS.md`, `config/.env.example`
- **Steps**:
  1. Env `ALLOW_QUERY_TOKEN=false`
  2. Envoyer request sans header mais avec `?token=...`
- **Expected**:
  - refus (log `AUTH_DENY`) si query token (et pas d’Authorization/header)
  - compat legacy si `ALLOW_QUERY_TOKEN=true`
- **Actual (avant)**: query token accepté sans restriction
- **Impact**: fuite secrets + replay potentiel
- **AC/DoD**:
  - `ALLOW_QUERY_TOKEN` documenté
  - gating effectif dans les 3 inbound workflows
- **Test Plan**:
  - `./scripts/integrity_gate.sh` (gating check)
  - `./scripts/smoke.sh`
- **Rollback**:
  - remettre l’ancien code (ou activer `ALLOW_QUERY_TOKEN=true`)
- **Estimation**: S
- **Dependencies**: None

### P0-OPS-001 — Add Integrity Gate (static)
- **Priority**: P0
- **Status**: ✅ DONE (patch 2026-01-22)
- **Description**: Ajout d’un gate reproductible pour éviter les regressions.
- **Scope**: `scripts/integrity_gate.sh`
- **Steps**:
  1. Run `./scripts/integrity_gate.sh`
- **Expected**: PASS
- **Impact**: Réduit risques de livraison cassée
- **AC/DoD**:
  - bash -n ok
  - scan placeholders ok
  - workflows JSON valid
  - DB bootstrap ordering ok
  - compose YAML parse ok (best-effort)
- **Test Plan**: `./scripts/integrity_gate.sh`
- **Rollback**: supprimer le script
- **Estimation**: S
- **Dependencies**: None

### P1-DB-002 — Index & retention policy for high-churn tables
- **Priority**: P1
- **Status**: TO DO
- **Description**: Ajouter/ajuster index pour `inbound_messages`, `security_events`, `outbound_messages` et policy de rétention (partition/cron).
- **Scope**: `db/migrations/*`, workflows W8_OPS (retention job)
- **Impact**: perf/coût Postgres
- **AC/DoD**:
  - migration idempotente
  - job de purge documenté et paramétrable
- **Test Plan**: EXPLAIN ANALYZE + charge tests
- **Rollback**: drop index / disable job
- **Estimation**: M
- **Dependencies**: P1-OBS-001

### P1-DB-003 — Add constraints + enums for event types
- **Priority**: P1
- **Status**: TO DO
- **Description**: Standardiser `security_events.event_type` / `workflow_errors` via CHECK constraints ou enums + table de référence.
- **Scope**: DB migration + docs
- **Impact**: qualité données & analytics
- **Estimation**: M

### P1-ARCH-002 — Multi-tenant routing contracts (formal)
- **Priority**: P1
- **Status**: TO DO
- **Description**: Formaliser contrats d’events (schema JSON) + versioning (v1/v2) pour webhooks.
- **Scope**: W1/W2/W3 parse + docs
- **Estimation**: M

### P1-ARCH-003 — Failure modes & SLOs (queue / outbox)
- **Priority**: P1
- **Status**: TO DO
- **Description**: Définir SLO (latence, taux d’erreur), DLQ strategy, alerting.
- **Scope**: W8_OPS + monitoring
- **Estimation**: M

### P1-OPS-002 — Backup & restore playbook
- **Priority**: P1
- **Status**: TO DO
- **Description**: Backup Postgres + Redis (si besoin) + rotation + tests de restore.
- **Scope**: docs + scripts
- **Estimation**: M

### P1-OBS-001 — Observability (metrics + dashboards)
- **Priority**: P1
- **Status**: TO DO
- **Description**: Export métriques (outbox backlog, deny rate, SSRF blocks, errors) vers Prometheus/Grafana ou logs structurés.
- **Scope**: W8_OPS + DB views
- **Estimation**: L

### P1-SEC-003 — Per-client scopes & RBAC admin endpoints
- **Priority**: P1
- **Status**: TO DO
- **Description**: Ajouter scopes par `api_clients.scopes` + enforcement.
- **Scope**: parse/auth context + DB
- **Estimation**: M

### P1-QA-002 — Test harness (docker-compose test + fixtures)
- **Priority**: P1
- **Status**: TO DO
- **Description**: Ajouter un compose de test + fixtures DB + scripts pour exécuter smoke automatiquement.
- **Scope**: docker/ + scripts + CI
- **Estimation**: M

---

## EPIC 1 — Paiement

### P2-DB-004 — Payment tables (socle P1)
- **Priority**: P2
- **Status**: TO DO
- **Description**: Ajouter tables `payments`, `payment_attempts` + idempotency.
- **Dependencies**: P1-ARCH-002

### PAY-001 — Init paiement (lien / instruction)
- **Priority**: P2
- **Status**: TO DO
- **Description**: Flow user pour init paiement (CIB/EDAHABIA/COD).

### PAY-002 — Webhook confirmation paiement
- **Priority**: P2
- **Status**: TO DO

### PAY-003 — Reconciliation & retry
- **Priority**: P2
- **Status**: TO DO

### PAY-004 — Refund / annulation
- **Priority**: P2
- **Status**: TO DO

---

## EPIC 2 — Livraison

### DEL-001 — Création livraison (wilaya/commune)
- **Priority**: P2
- **Status**: TO DO

### DEL-002 — Gestion exceptions (adresse imprécise, indisponible)
- **Priority**: P2
- **Status**: TO DO

### DEL-003 — SLA & fenêtre livraison
- **Priority**: P2
- **Status**: TO DO

---

## EPIC 3 — Tracking

### TRK-001 — Tracking commande client (WhatsApp)
- **Priority**: P2
- **Status**: TO DO

### TRK-002 — Tracking admin (console)
- **Priority**: P2
- **Status**: TO DO

---

## EPIC 4 — Offline

### OFF-001 — Mode offline (cache menu + commande)
- **Priority**: P2
- **Status**: TO DO

### OFF-002 — Sync outbox quand réseau revient
- **Priority**: P2
- **Status**: TO DO

---

## EPIC 5 — Langues

### L10N-001 — FR/AR (Darija) intents & templates
- **Priority**: P2
- **Status**: TO DO

### L10N-002 — Switch langue par user
- **Priority**: P2
- **Status**: TO DO

---

## EPIC 6 — Support

### SUP-001 — Handoff humain (agent)
- **Priority**: P2
- **Status**: TO DO

### SUP-002 — Knowledge base FAQ (RAG light)
- **Priority**: P2
- **Status**: TO DO

---

## EPIC 7 — Anti-fraude

### FRAUD-001 — Détection spam / bot
- **Priority**: P2
- **Status**: TO DO

### FRAUD-002 — Quarantine policies & auto-release
- **Priority**: P2
- **Status**: TO DO

---

## EPIC 8 — Growth

### GROW-001 — Acquisition (WA click-to-chat + QR menu)
- **Priority**: P2
- **Status**: TO DO

### GROW-002 — Analytics conversion (funnel)
- **Priority**: P2
- **Status**: TO DO
