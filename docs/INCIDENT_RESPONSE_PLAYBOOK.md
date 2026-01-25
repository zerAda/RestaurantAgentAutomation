# Incident Response Playbook (P0-OPS-02)

This project is WhatsApp-first and runs in a VPS environment with unstable networks (Algeria). Incidents must be handled fast with clear ownership and rollback-first mindset.

## Severity Levels
- **SEV0**: Full outage (inbound down, outbox not sending, DB unavailable)
- **SEV1**: Partial outage (WhatsApp send failing, SLO breaches, DLQ growing)
- **SEV2**: Degraded (high latency, increased retries, intermittent provider errors)
- **SEV3**: Minor (single tenant issue, template bug)

## Golden Signals
- Outbox pending age (`outbound_messages` oldest PENDING/RETRY)
- Pending count (`outbound_messages` PENDING/RETRY)
- DLQ count
- Auth denies spikes (`security_events`)
- Workflow errors per hour (`workflow_errors`)

## First 10 minutes checklist
1. Confirm scope: SEV level, affected channel(s), tenant(s)
2. Check gateway health (Traefik + Nginx), confirm webhook ingress
3. Check Postgres health + disk space
4. Check Redis health (queue)
5. Check outbox backlog + DLQ
6. Apply safe mitigation: reduce traffic, enable throttling/quarantine, increase retry delays

## Common Incidents & Runbooks
### OUTBOX_BACKLOG (SLO breach)
- Symptoms: `SLO_BREACH` events, pending age growing
- Actions:
  - Verify W8_OPS is active and running every 1 min
  - Check provider send URL reachable (`WA_SEND_URL`)
  - Temporarily increase `OUTBOX_BASE_DELAY_SEC` to reduce pressure
  - If provider is down: pause sending (set `WA_SEND_URL=`) and keep queue; communicate to ops

### WA_PROVIDER_5XX
- Increase backoff, cap concurrency, keep idempotency headers enabled.

### AUTH_DENY_SPIKE / ATTACK
- Ensure Nginx rate-limit is active
- Ensure `ALLOW_QUERY_TOKEN=false`
- Ensure `LEGACY_SHARED_ALLOWED=false`
- If needed: enable quarantine / throttle rules

## Post-Incident
- Write timeline (what, when)
- Root cause + prevention tickets
- Verify backlog drains and SLO returns to green
