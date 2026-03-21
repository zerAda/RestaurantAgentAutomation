# SLO — Queue/Outbox (P1-ARCH-003)

This system relies on an **outbox** table (`outbound_messages`) and a **queue worker** workflow (`W8_OPS`) that delivers messages to provider send APIs.

This document defines the SLOs and how they are measured.

## SLOs

### SLO-1 — Inbound → Outbox queued latency (p95)

**Goal:** the time from inbound message reception to the moment the corresponding reply is enqueued in the outbox stays low.

- Metric: `inbound_to_outbox_ms_p95`
- Window: `SLO_WINDOW_MIN` (default **15 min**)
- Target: `<= SLO_INBOUND_TO_OUTBOX_P95_MS` (default **2000 ms**)
- Measurement (current implementation):
  - Joins `inbound_messages.received_at` with `outbound_messages.created_at`
  - Match is done using `outbound_messages.dedupe_key = 'msg:<channel>:<msg_id>'`
  - Notes:
    - This measures the common "reply to inbound message" path.
    - Order-based replies (`dedupe_key = 'order:...'`) are not included by design.

### SLO-2 — Outbox pending age (max)

**Goal:** messages should not remain stuck in `PENDING` / `RETRY`.

- Metric: `outbox_pending_age_max_sec`
- Target: `<= SLO_OUTBOX_PENDING_AGE_MAX_SEC` (default **600 sec**)
- Measurement:
  - `max(now() - created_at)` for rows in `status IN ('PENDING','RETRY')`

### SLO-3 — DLQ rate (windowed)

**Goal:** DLQ should stay rare.

- Metric: `dlq_rate`
- Target: `<= SLO_DLQ_RATE_MAX` (default **0.05**)
- Measurement:
  - Windowed over `updated_at > now() - SLO_WINDOW_MIN`
  - Rate = `DLQ / (DLQ + SENT)` within the window

## Alerting

`W8_OPS` runs SLO checks every 5 minutes. Breaches trigger:

1. `security_events` entry (`SLO_BREACH`, severity depends on the breached SLO)
2. Optional webhook call to `ALERT_WEBHOOK_URL` (structured JSON)

### Default thresholds (override via env)

- `SLO_WINDOW_MIN=15`
- `SLO_INBOUND_TO_OUTBOX_P95_MS=2000`
- `SLO_OUTBOX_PENDING_AGE_MAX_SEC=600`
- `SLO_DLQ_RATE_MAX=0.05`
- `SLO_DLQ_COUNT_MAX=5` (extra safety)

## Runbook

### If SLO-1 breaches (p95 latency high)

1. Check `W8_OPS` executions: are workers running? is Redis healthy?
2. Check Postgres health and `outbound_messages` growth.
3. Look for spikes in `workflow_errors` and `security_events`.
4. If the system is overloaded, temporarily lower inbound rate limits or scale workers.

### If SLO-2 breaches (pending age high)

1. Check if provider send APIs are failing (timeouts/401/5xx).
2. Verify `WA_SEND_URL/IG_SEND_URL/MSG_SEND_URL` and API tokens.
3. Inspect oldest pending messages (`outbound_messages`), especially `last_error`.
4. Consider pausing inbound or increasing worker capacity until the backlog drains.

### If SLO-3 breaches (DLQ rate high)

1. Inspect recent DLQ messages (`status='DLQ'` and `updated_at` in window).
2. Common causes:
   - wrong provider token
   - provider API outage
   - bad payload template mapping
3. Fix root cause, then **requeue**:
   - set `status='RETRY'`, `attempts=0`, `next_retry_at=now()` for selected DLQ rows
4. If uncertain, keep DLQ as is and escalate (avoid loops).

## Rollback

- Revert to the previous `W8_OPS.json` and redeploy.
- Disable SLO alerts by clearing `ALERT_WEBHOOK_URL` or setting thresholds to permissive values.
