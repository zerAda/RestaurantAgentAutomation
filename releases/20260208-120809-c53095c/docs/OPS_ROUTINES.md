# OPS Routines (Daily / Weekly / Monthly)

## Daily (10 min)
- Check outbox backlog (pending age + count)
- Check DLQ count
- Review top `workflow_errors` last 24h
- Review `security_events` spikes (AUTH_DENY, RATE_LIMIT, SLO_BREACH)

## Weekly
- Restore drill (snapshot + restore into staging)
- Review SLO trends and adjust thresholds
- Review anti-fraud/quarantine stats

## Monthly
- Rotate tokens (WA provider, api_clients)
- Re-run load test protocol
- Review retention job results (DB size)
