---
name: observability
description: Health endpoints, structured logging, correlation IDs, monitoring workflows, and alert hooks.
when_to_use:
  - Production readiness review
  - Incident debugging
  - Adding health checks
  - Setting up alerting
---

# Observability & Health

## Health infrastructure

| Component | Health mechanism |
|-----------|-----------------|
| n8n | `W16_HEALTHZ.json` (webhook endpoint) |
| Monitoring | `W17_HEALTH_MONITOR.json` (active checks) |
| Deep check | `scripts/deep-health-check.sh` (all services) |
| CI health | `.github/workflows/health-monitor.yml` (scheduled) |
| CI action | `.github/actions/health-check/action.yml` (retry + response time) |

## Logging requirements

- Structured JSON logs with: timestamp, level, service, correlation_id, route, status, latency_ms
- Correlation ID: propagated from gateway (`X-Request-ID`) through workflows to DB writes
- Token/PII redaction in all log outputs
- Nginx access log: custom format in `infra/gateway/nginx.conf` (verify no token logging)

## Monitoring endpoints

```bash
# Gateway health
curl https://api.<domain>/v1/health

# n8n healthz workflow
curl https://api.<domain>/webhook/healthz

# Deep health (all services)
scripts/deep-health-check.sh
```

## Alert hooks

- Slack: via `.github/actions/notify/` composite action (Block Kit format)
- Discord: via same action (embed format, optional)
- Configured per-workflow with `webhook-url` and `discord-webhook-url` inputs

## DORA metrics

- Tracked by `scripts/dora_metrics.sh`
- Dashboard: `docs/DORA_DASHBOARD.md`
- Metrics: deployment frequency, lead time, MTTR, change failure rate

## Incident triage (first 10 minutes)

1. `curl -s https://api.<domain>/v1/health` — is API responding?
2. `ssh deploy@<vps> docker ps --format "table {{.Names}}\t{{.Status}}"` — containers up?
3. `ssh deploy@<vps> docker logs --tail 50 gateway` — gateway errors?
4. `ssh deploy@<vps> docker logs --tail 50 n8n-main` — n8n errors?
5. `ssh deploy@<vps> redis-cli -a <pw> LLEN bull:default:wait` — queue depth?

## Deliverables

- Health endpoints verified (expected output documented)
- Log redaction confirmed (no secrets/PII in logs)
- Alert hook tested (notification received)
