# TEST_REPORT — RESTO BOT

## v3.3.3 — Full CI/CD Green + VPS Health (2026-02-22)

### CI Pipeline (13/13 GREEN) — commit f4159b1

| Job | Status | Duration |
|-----|--------|----------|
| Security Scan (10 jobs) | PASS | ~30s |
| Integrity Gate | PASS | ~15s |
| Lint & Validate | PASS | ~20s |
| Python Tests | PASS | ~25s |
| Integration Tests (PG15/16) | PASS | ~45s |
| Frontend Lint | PASS | ~15s |
| Docker Build (cms, kiosk, admin) | PASS | ~2m |
| Build & Push GHCR | PASS | ~9m |
| **Test Harness (Full Stack)** | **PASS** | **1m39s** |
| Performance Baseline | PASS | ~24s |

#### Test Harness Details (run 22278334134)

- webhook_entity DB records: 8 verified
- Active workflows: 7 verified
- All 7 webhook paths verified in DB (v1/inbound/whatsapp, instagram, messenger + admin/customer endpoints)
- Tracking trigger: non-blocking warning (fn_ruthless_normalize type mismatch)

### CD Pipeline (15/15 GREEN) — run 22278484906

| Job | Status | Duration |
|-----|--------|----------|
| Validate Inputs | PASS | 3s |
| Pre-flight Checks | PASS | 15s |
| Security Gate | PASS | 9s |
| Deploy to Staging | PASS | 53s |
| Smoke Battery (Staging) | PASS | 6s |
| Approve Production Deploy | PASS | 4s |
| Pre-deploy Backup | PASS | 8s |
| Deploy (vps-primary) | PASS | 28s |
| Smoke (whatsapp) | PASS | 7s |
| Smoke (internal) | PASS | 9s |
| Smoke (instagram) | PASS | 5s |
| Smoke (messenger) | PASS | 8s |
| DORA Metrics | PASS | 9s |
| Post-deploy Cleanup | PASS | 11s |
| Post-deployment | PASS | 3s |

### VPS Service Health (post-deploy, 2026-02-22 19:50 UTC)

```text
CONTAINER                   STATUS
traefik-1                   Up (running)
gateway-1                   Up (healthy)
n8n-main-1                  Up (running, healthz OK via gateway)
n8n-worker-1                Up (running)
cms-1                       Up (healthy)
adminer-1                   Up (running)
postgres-1                  Up (healthy)
redis-1                     Up (healthy, PONG)
admin-dashboard-1           Up (healthy)
kiosk-app-1                 Up (healthy)
```

### HTTPS Endpoint Verification

| Endpoint | Expected | Actual |
|----------|----------|--------|
| `https://api.srv1258231.hstgr.cloud/healthz` | 200 | 200 |
| `https://kiosk.srv1258231.hstgr.cloud/` | 200 | 200 |
| `https://admin.srv1258231.hstgr.cloud/` | 401 (BasicAuth) | 401 |
| `https://console.srv1258231.hstgr.cloud/` | 401 (BasicAuth) | 401 |
| `https://cms.srv1258231.hstgr.cloud/` | 302 (Strapi redirect) | 302 |

### Internal Service Health

| Service | Check | Result |
|---------|-------|--------|
| n8n-main | `curl http://n8n-main:5678/healthz` (via gateway) | `{"status":"ok"}` |
| postgres | `pg_isready -U n8n` | accepting connections |
| redis | `redis-cli ping` | PONG |

### VPS System Resources

| Metric | Value |
|--------|-------|
| Disk | 23% (22G/96G) — was 94% before cleanup |
| Memory | 1.6G used / 7.8G total (6.2G available) |
| Load | 0.21 (1-min avg) |

### Known Limitations

- Cosign image signing: COSIGN_PASSWORD mismatch (warnings only, non-blocking)
- `fn_ruthless_normalize` trigger: causes `text = uuid` type mismatch in tracking chain (non-blocking)
- n8n workflow activation warnings: W4, W5, W6, W7, W12, W14 fail activation (sub-workflows without trigger nodes, invoked by parent workflows)
- Broken SQL in `bootstrap.sql:2417` (pre-existing, non-blocking)

---

# TEST_REPORT — RESTO BOT v3.1 — 2026-01-22

Couvre :
- SYSTEM-2 : contracts inbound versionnés + SLO/failure modes outbox
- SYSTEM-3 : backup/restore + scopes/RBAC + test harness
- EPIC2 : DEL-001/002/003 (livraison)

## 1) Checks statiques — PASS (exécutés dans ce sandbox)

### 1.1 Integrity Gate
```bash
./scripts/integrity_gate.sh
```
Attendu :
- validation JSON des workflows
- unit tests JSON Schema (`scripts/validate_contracts.py`)
- check DB bootstrap ordering
- présence des livrables (SYSTEM-2/3 + EPIC2 : migrations, workflows W10/W11, templates)

### 1.2 Unit tests contrats JSON Schema
```bash
python3 scripts/validate_contracts.py
```
Cas couverts :
- `tests/contracts/valid_v1.json` → PASS
- `tests/contracts/valid_v2.json` → PASS
- `tests/contracts/invalid_missing_msg_id.json` → FAIL attendu
- `tests/contracts/invalid_wrong_types.json` → FAIL attendu

## 2) Runtime checks — à exécuter sur VPS/local (bloquants Go‑Live)

> Non exécutables dans ce sandbox (dépendance `docker` absente). Les scripts sont fournis.

### 2.1 Harness (stack test)
```bash
./scripts/test_harness.sh
```
Attendu :
- migrations (replay x2) OK
- seed demo delivery OK
- import workflows OK
- smoke inbound legacy OK
- EPIC2 : delivery quote OK + zone invalid OK
- EPIC3 : admin orders list OK + tracking outbox (1 msg/statut, no-op same statut)

### 2.2 EPIC2 — scénarios livraison
1) Seed demo
```bash
psql "$DATABASE_URL" -f db/seed_delivery_demo.sql
```

2) Quote valide
```bash
curl -X POST "$BASE_URL/v1/customer/delivery/quote" \
  -H "x-webhook-token: <customer_token>" -H "Content-Type: application/json" \
  -d '{"wilaya":"Alger","commune":"Hydra","total_cents":2500}'
```
Attendu : `ok=true`, `reason=OK`, `fee.final_cents>=DELIVERY_FEE_MIN_CENTS`.

3) Zone invalide
```bash
curl -X POST "$BASE_URL/v1/customer/delivery/quote" \
  -H "x-webhook-token: <customer_token>" -H "Content-Type: application/json" \
  -d '{"wilaya":"X","commune":"Y","total_cents":2500}'
```
Attendu : `ok=false`, `code=DELIVERY_ZONE_NOT_FOUND` + log `security_events`.

4) Slots (si `DELIVERY_SLOTS_ENABLED=true`)
- Quote retourne `slots[]`.
- Choix slot → réservation via `reserve_delivery_slot(order_id, slot_id)`.

## 3) Notes
- Les événements delivery sont loggés via `security_events` (ex: `DELIVERY_ZONE_NOT_FOUND`, `ADDRESS_AMBIGUOUS`, `SLOT_FULL`).
- Rollback EPIC2 : `docs/ROLLBACK_EPIC2_DELIVERY.md`.


### 2.3 EPIC3 — scénarios tracking
1) Admin orders list
```bash
curl -X GET "$BASE_URL/v1/admin/orders?limit=10" -H "x-webhook-token: <admin_token>"
```
Attendu : `ok=true`, `orders[]`.

2) Status chain (DB)
Mettre à jour `orders.status` sur un order WhatsApp et vérifier :
- `order_status_history` timeline
- `outbound_messages` contient 1 message par customer_status (idempotent).

Rollback EPIC3 : `docs/ROLLBACK_EPIC3_TRACKING.md`.

## 2026-01-23 — EPIC5 L10N
- ✅ scripts/integrity_gate.sh PASS
- ✅ scripts/test_darja_intents.py PASS (61 phrases)
- ✅ scripts/test_l10n_script_detection.py PASS (20 cases)
- ✅ scripts/test_template_render.py PASS (10 cases)
- ⚠️ scripts/test_harness.sh requires Docker; not executed in this environment (dependency missing).
## 2026-01-23 — P0 Additions (v3.2.3)
- **P0-OPS-01 Alerting**: W8 emits SLO alerts to `ALERT_WEBHOOK_URL` with cooldown using `ops_kv`.
- **P0-OPS-02 Runbooks**: Added `docs/INCIDENT_RESPONSE_PLAYBOOK.md`, `docs/OPS_ROUTINES.md`, `docs/ALERTING.md`.
- **P0-OPS-03 Outbox idempotency**: `O3 - Send Outbox` adds idempotency headers + embeds `client_message_id`/`dedupe_key` into provider body; treats HTTP 409 as idempotent duplicate and marks SENT.
- **Meta webhook verify**: Added `W0_META_VERIFY_WA.json` to answer GET `hub.challenge` on `/v1/inbound/whatsapp`.
- **Inbound security**: W1 webhook now captures `rawBody`; validates `X-Hub-Signature-256` when `META_SIGNATURE_REQUIRED=true`; blocks legacy shared token when `LEGACY_SHARED_ALLOWED=false`.
- **Cleanup**: Removed `*.patched` duplicates; updated compose and integrity gate accordingly.

### Executed checks (this environment)
- `scripts/integrity_gate.sh` : **PASS**
- `scripts/test_harness.sh` : not executable here (requires Docker). The harness remains CI/ops runnable on the VPS host.
