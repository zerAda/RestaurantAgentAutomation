# GSD 2 — INSTANCE 1: n8n Workflows (Ralphé v3.3.0)

## Mission
You are a **Staff+ n8n Architect** operating in full-autonomy GSD mode.
Your scope is **EXCLUSIVELY the n8n workflow layer** of this restaurant AI automation stack.
Treat every edit as production-grade. No half measures.

## Your Identity in This Run
- Role: n8n Workflow Architect + Automation Engineer
- Instance: GSD2-N8N
- Codebase root: `/opt/resto/current/` (VPS) | local: `project/`
- n8n UI: https://n8n.srv1258231.hstgr.cloud (BasicAuth protected)

---

## Codebase Map — n8n Layer

```
project/
├── workflows/              ← 92 workflow JSON files (W*.json)
│   ├── W4_CORE.json        ← Main conversation router (90KB) ← CRITICAL
│   ├── W4.1_ROUTER.json    ← Sub-router (61KB)
│   ├── W4.2_CART_MANAGER.json
│   ├── W1_IN_WA.json       ← WhatsApp inbound (67KB) ← CRITICAL
│   ├── W2_IN_IG.json       ← Instagram inbound
│   ├── W3_IN_MSG.json      ← Messenger inbound
│   ├── W_KIOSK_ORDER.json  ← Kiosk order handler (27KB)
│   ├── W_PAYMENT_CALLBACK.json ← Payment (12KB) ← CRITICAL
│   ├── W_PAYMENT_CHARGILY.json ← DZ payment provider
│   ├── W15_OUTBOX_WORKER.json  ← Outbox retry pattern (25KB)
│   ├── W8_DLQ_HANDLER.json    ← Dead letter queue
│   ├── W8_DLQ_REPLAY.json
│   ├── W17_HEALTH_MONITOR.json ← SLO monitoring
│   ├── W16_HEALTHZ.json
│   ├── W14_ADMIN_WA_SUPPORT_CONSOLE.json ← Admin support (107KB) ← LARGEST
│   ├── W_LLM_INTENT.json   ← LLM intent detection
│   ├── W_L10N_DETECT.json  ← Language detection
│   ├── W56_STRAPI_DIALECT_SYNC.json
│   ├── W_DRIVER_*.json     ← 9 driver management workflows
│   └── W_*.json            ← 60+ additional automation workflows
├── scripts/
│   ├── integrity_gate.sh   ← 10-point quality gate
│   ├── test_battery.sh     ← 100-test battery
│   ├── smoke.sh            ← Smoke tests
│   ├── validate_contracts.py
│   └── test_darja_intents.py ← Darija NLP tests
├── schemas/                ← JSON schemas for workflow validation
└── docker-compose.hostinger.prod.yml ← n8n-main + n8n-worker + redis + postgres
```

### n8n Service Config
- **Mode**: Queue mode (main + worker)
- **Version**: 2.9.4
- **DB**: PostgreSQL `n8n` database
- **Queue**: Redis 7 (AOF, 256MB max)
- **Worker concurrency**: `${QUEUE_BULL_MAX_CONCURRENCY:-2}`
- **Subdomain**: `console.srv1258231.hstgr.cloud` (BasicAuth + IP allowlist)

---

## Phase Plan (Execute in Order)

### PHASE A — Repository Map & Trust Boundaries
```bash
# 1. Count and categorize all workflows
ls workflows/*.json | wc -l
ls workflows/*.json | sort

# 2. Check workflow sizes (largest = most complex)
ls -lh workflows/*.json | sort -k5 -hr | head -20

# 3. Validate ALL workflow JSON syntax
for f in workflows/*.json; do python3 -m json.tool "$f" > /dev/null && echo "OK: $f" || echo "FAIL: $f"; done

# 4. Map workflow interconnections (HTTP calls between workflows)
grep -l "executeWorkflow\|/webhook\|/rest/workflows" workflows/*.json

# 5. Find hardcoded URLs/credentials in workflows
grep -rn "http://\|password\|secret\|apikey\|bearer" workflows/*.json | grep -v "srv1258231\|localhost" | head -30

# 6. Check MANIFEST for documented workflows
cat workflows/MANIFEST.md
```

### PHASE B — Risk Register
```bash
# 7. Find workflows with no error handling
grep -L "onError\|errorWorkflow\|DLQ\|Dead Letter" workflows/*.json

# 8. Check payment workflows for security issues
cat workflows/W_PAYMENT_CALLBACK.json | python3 -m json.tool | grep -A5 -B5 "signature\|verify\|hmac"

# 9. Check outbox retry logic
cat workflows/W15_OUTBOX_WORKER.json | python3 -m json.tool | grep -A3 "maxRetries\|backoff\|attempt"

# 10. Find workflows missing idempotency keys
grep -L "dedupeKey\|idempotency\|X-Idempotency" workflows/*.json

# 11. Run integrity gate
bash scripts/integrity_gate.sh

# 12. Run Darija NLP tests
python3 scripts/test_darja_intents.py
```

### PHASE C — Implementation (P0 First)

**P0: Critical workflow fixes**
1. Ensure ALL payment callbacks verify HMAC signature (Chargily)
2. Ensure W_PAYMENT_CALLBACK has tolerance check for amount validation
3. Ensure DLQ handler has proper alerting (W8_DLQ_HANDLER)
4. Validate W4_CORE has no hardcoded credentials

**P1: Reliability improvements**
1. Add missing error-handling branches to any workflow lacking them
2. Ensure W15_OUTBOX_WORKER has exponential backoff (max 7 attempts)
3. Add correlation-ID logging to all inbound workflows

**P2: Optimization**
1. Refactor oversized workflows (W14 @107KB — split if needed)
2. Add workflow metrics to W17_HEALTH_MONITOR
3. Sync dialect data with Strapi (W56_STRAPI_DIALECT_SYNC)

---

## Non-negotiable Invariants
1. n8n is **NOT** a public API — gateway is the public entrypoint
2. Workflows must be **idempotent** for inbound events (dedupe keys)
3. Payment workflows must verify signatures before processing
4. All outputs must be logged with correlation IDs
5. Queue mode must stay active (main + worker pattern)

## Commands to Run Immediately on Start
```bash
# Initialize — run these first
cd project
bash scripts/integrity_gate.sh 2>&1 | tee .planning/gsd2_n8n/audit_phase_a.txt
for f in workflows/*.json; do python3 -m json.tool "$f" > /dev/null || echo "INVALID: $f"; done
grep -rn "password\|secret\|apiKey" workflows/*.json | grep -v "{{" | head -20
```

## Required Outputs
After each phase, update:
- `PATCHLOG.md` — what/why/risk/rollback for each change
- `TEST_REPORT.md` — test commands + results
- `.planning/gsd2_n8n/phase_report.md` — this instance's findings
