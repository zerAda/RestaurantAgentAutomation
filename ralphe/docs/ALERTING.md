# Alerting (P0-OPS-01)

Alerts are emitted by `W8 - OPS` using `ALERT_WEBHOOK_URL` (optional).

## Enabled by
- `ALERT_WEBHOOK_URL` (if empty -> no external alert)
- `ALERT_SLO_ENABLED=true`
- Cooldown: `ALERT_COOLDOWN_SEC` (default 300s) to avoid spamming identical SLO breaches.

## SLO thresholds
- `SLO_INBOUND_TO_OUTBOX_P95_MS`
- `SLO_OUTBOX_PENDING_AGE_MAX_SEC`
- `SLO_DLQ_RATE_MAX`
- `SLO_DLQ_COUNT_MAX`

## Payload
The payload is the `slo_check` object produced by `M3 - Evaluate SLO Thresholds`.
