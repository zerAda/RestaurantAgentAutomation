# TEST_REPORT — RESTO BOT

## v3.3.2 — CD Pipeline Verification (2026-02-22)

### CI Pipeline (commit 4e04261)

| Job | Status |
|-----|--------|
| Security Scan (10 jobs) | PASS |
| Integrity Gate | PASS |
| Lint & Validate | PASS |
| Python Tests | PASS |
| Integration Tests (PG15/16) | PASS |
| Frontend Lint | PASS |
| Docker Build (cms, kiosk, admin) | PASS |
| Build & Push GHCR | PASS |

### CD Pipeline Verification

| Stage | Result | Notes |
|-------|--------|-------|
| Validate | PASS | Compose syntax + env validation |
| Preflight | PASS | VPS reachability + disk/memory checks |
| Security Gate | PASS | Gitleaks + Trivy + SBOM |
| Deploy Staging | PASS | Full stack on staging port range |
| Smoke Staging | PASS | Healthz + inbound endpoint checks |
| Approve | PASS | Auto-approved (environment protection) |
| Deploy Production | PASS | Atomic symlink cutover |
| Smoke Production | PASS | External endpoint verification |
| DORA Metrics | PASS | Deployment frequency + lead time |
| Cleanup | PASS | Release pruning (keep 5) |
| Post-Deploy | PASS | Rollback gate (no rollback needed) |

### VPS Service Health (post-deploy)

```
$ docker compose ps
NAME                STATUS          PORTS
traefik-1           Up              0.0.0.0:80, 0.0.0.0:443, 127.0.0.1:8080
gateway-1           Up (healthy)    80, 8080
n8n-main-1          Up              5678
n8n-worker-1        Up              5678
cms-1               Up (healthy)    1337
adminer-1           Up              8080
postgres-1          Up (healthy)    5432
redis-1             Up (healthy)    6379
admin-dashboard-1   Up (healthy)    80, 8080
kiosk-app-1         Up (healthy)    80, 8080
```

### HTTPS Endpoint Verification

| Endpoint | Expected | Actual |
|----------|----------|--------|
| `https://api.srv1258231.hstgr.cloud/healthz` | 200 `ok` | 200 `ok` |
| `https://console.srv1258231.hstgr.cloud/` | 401 BasicAuth | 401 BasicAuth |
| `http://api.srv1258231.hstgr.cloud/` | 301 → HTTPS | 301 → HTTPS |

### Known Limitations

- Cosign image signing: COSIGN_PASSWORD mismatch (non-blocking, documented)
- Backup job: skips first deploy (expected behavior, works on subsequent deploys)
- Smoke battery: external channel tests (WhatsApp/Instagram/Messenger) require real API tokens
- Disk usage: 76% (warning threshold, non-blocking)

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
