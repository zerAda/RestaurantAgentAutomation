# AGENT 06 — SLO Alerting & Monitoring (P0-OPS-01)

## Mission
Implement alerting for SLO violations: outbox backlog, DLQ growth, error rates.

## Priority
**P0 - HIGH** - Required for production observability.

## Problem Statement
- No alerts when outbox backs up
- No alerts when DLQ grows
- No alerts when error rates spike
- Silent failures → customer impact before detection

## Solution
1. Add alert queries to W8_OPS workflow
2. Configure alert thresholds via env vars
3. Send alerts to webhook (Slack/Discord/etc.)
4. Create runbook for each alert type

## Files Modified
- `config/.env.example`
- `workflows/W8_OPS.json`
- `docs/ALERTING.md`
- `infra/alerting/rules.yaml`

## Implementation

### .env.example additions
```env
# =========================
# Alerting (P0-OPS-01)
# =========================
# Alert webhook URL (Slack, Discord, custom)
ALERT_WEBHOOK_URL=https://hooks.slack.com/services/xxx

# Outbox SLO: max pending age (seconds)
ALERT_OUTBOX_PENDING_AGE_SEC=60

# Outbox SLO: max pending count
ALERT_OUTBOX_PENDING_COUNT=100

# DLQ SLO: max DLQ count before alert
ALERT_DLQ_COUNT=10

# Error rate: max errors per hour
ALERT_ERRORS_PER_HOUR=50

# Auth deny: max denies per hour (attack indicator)
ALERT_AUTH_DENY_PER_HOUR=100

# Alert cooldown (seconds between same alert type)
ALERT_COOLDOWN_SEC=300
```

### Alert Queries (W8_OPS)
```sql
-- Outbox pending age (p95)
SELECT 
  EXTRACT(EPOCH FROM (now() - MIN(created_at))) AS oldest_pending_sec,
  COUNT(*) AS pending_count
FROM outbound_messages 
WHERE status IN ('PENDING', 'RETRY');

-- DLQ count
SELECT COUNT(*) AS dlq_count 
FROM outbound_messages 
WHERE status = 'DLQ';

-- Errors per hour
SELECT COUNT(*) AS errors_hour
FROM workflow_errors
WHERE created_at > now() - interval '1 hour';

-- Auth denies per hour
SELECT COUNT(*) AS auth_denies_hour
FROM security_events
WHERE event_type = 'AUTH_DENY'
  AND created_at > now() - interval '1 hour';
```

### Alert Payload Format
```json
{
  "alert_type": "OUTBOX_BACKLOG",
  "severity": "HIGH",
  "message": "Outbox pending age exceeds SLO",
  "details": {
    "current_value": 120,
    "threshold": 60,
    "unit": "seconds"
  },
  "runbook_url": "https://docs/runbook#outbox-backlog",
  "timestamp": "2026-01-23T15:30:00Z"
}
```

### Alert Types
| Alert Type | Threshold | Severity | Runbook |
|------------|-----------|----------|---------|
| `OUTBOX_BACKLOG` | pending_age > 60s | HIGH | Check provider, increase workers |
| `OUTBOX_COUNT` | pending > 100 | MEDIUM | Scale workers, check provider |
| `DLQ_GROWTH` | dlq > 10 | HIGH | Investigate failures, retry manually |
| `ERROR_SPIKE` | errors/h > 50 | HIGH | Check logs, recent deployments |
| `AUTH_DENY_SPIKE` | denies/h > 100 | CRITICAL | Possible attack, check IPs |
| `DB_CHURN` | table size > threshold | MEDIUM | Run retention, check indexes |

## Rollback
Set `ALERT_WEBHOOK_URL=` (empty) to disable alerts.

## Tests
```bash
# Trigger test alert
curl -X POST "$ALERT_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"alert_type":"TEST","message":"Alert system test"}'
```

## Validation Checklist
- [ ] Alerts fire when thresholds exceeded
- [ ] Cooldown prevents alert spam
- [ ] Alert payload includes actionable info
- [ ] Runbook links work
- [ ] Slack/Discord integration works
