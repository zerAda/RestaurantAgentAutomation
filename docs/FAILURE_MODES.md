# Failure Modes — Queue/Outbox (P1-ARCH-003)

This document lists the main failure modes, detection signals, and operational actions.

## FM-1 — Provider send API unavailable / unstable

**Symptoms**
- `outbound_messages` stuck in `RETRY`
- `outbox_pending_age_max_sec` breaches (SLO-2)
- `last_error` contains timeouts / 5xx

**Detection**
- `W8_OPS` SLO checks
- `workflow_errors` spikes for node `O3 - Send Outbox`

**Action**
- Confirm provider status
- Verify network/DNS
- Increase `OUTBOX_MAX_DELAY_SEC` temporarily if provider is rate-limiting
- Escalate if outage persists

## FM-2 — Bad credentials / 401/403

**Symptoms**
- DLQ growth after `OUTBOX_MAX_ATTEMPTS`
- `dlq_rate` breaches (SLO-3)
- `last_error` contains 401/403

**Action**
- Rotate credentials
- Requeue DLQ rows after fix (see `docs/SLO.md` runbook)

## FM-3 — DB locked / slow queries

**Symptoms**
- `inbound_to_outbox_ms_p95` breaches (SLO-1)
- Long-running queries in Postgres
- Growing `workflow_errors` on DB nodes

**Action**
- Check DB CPU/IO
- Inspect slow queries, missing indexes
- Temporarily reduce inbound rates

## FM-4 — Redis / queue worker failure

**Symptoms**
- `W8_OPS` not executing on schedule
- Pending age grows quickly
- No `SENT` updates

**Action**
- Check Redis health and n8n worker logs
- Restart worker containers
- Validate `EXECUTIONS_MODE=queue` config

## FM-5 — Schema validation failures (inbound)

**Symptoms**
- HTTP 400 responses on inbound endpoints
- `security_events` spikes on `CONTRACT_VALIDATION_FAILED`

**Action**
- Identify caller sending malformed payloads
- Verify contract version header/body
- Fix upstream serializer or downgrade to v1 until ready

## FM-6 — DLQ flood (systemic)

**Symptoms**
- `SLO_DLQ_COUNT_MAX` exceeded
- Alert storm

**Action**
- Identify cause (credentials, outage, bad template)
- Stop the bleeding: temporarily disable outbound sending by setting provider URLs empty (forces DLQ) **only if required**
- Escalate to on-call and product owner

## Escalation policy

- **HIGH:** SLO-2 breach > 2 cycles or DLQ rate > threshold
- **CRITICAL:** pending age > 1 hour OR DLQ flood continues > 30 min

Escalate to infrastructure owner and business owner. Keep a timeline and captured evidence (alerts, query outputs).
