---
name: n8n_queue_sre
description: Ensure n8n queue mode reliability - idempotency, DLQ, outbox, worker scaling, timeout coherence.
when_to_use:
  - Queue backlog or stuck executions
  - Duplicate processing detected
  - Scaling workers
  - Production readiness review
  - Adding new workflows
---

# n8n Queue SRE

## Topology (prod)

- `n8n-main`: webhook receiver, UI (queue mode enabled)
- `n8n-worker`: execution worker (separate container, same image)
- `redis`: queue backend (password-protected, maxmemory with LRU eviction)
- Config: `docker-compose.hostinger.prod.yml`

## Non-negotiables

1. Webhooks ACK fast (respond immediately, process async via queue)
2. Idempotency gate at ingestion (dedupe by message/event ID before DB write)
3. Retries with exponential backoff; cap at 3 retries
4. Dead-letter path: `W8_DLQ_HANDLER.json` captures failures, `W8_DLQ_REPLAY.json` retries
5. Outbox pattern: `W15_OUTBOX_WORKER.json` for reliable outbound delivery
6. Worker concurrency explicit: `EXECUTIONS_CONCURRENCY` env var
7. Redis persistence decision documented (AOF vs RDB vs none)

## Timeout coherence

All timeouts must be consistent across the chain:

| Layer | Setting | Recommended |
|-------|---------|-------------|
| Traefik | `respondingTimeouts.readTimeout` | 60s |
| Nginx | `proxy_read_timeout` | 55s |
| n8n | `EXECUTIONS_TIMEOUT` | 300s (workflow level) |
| n8n webhook | `responseMode: responseNode` | immediate ACK |

## Key workflows

| Workflow | Purpose |
|----------|---------|
| W8_DLQ_HANDLER | Captures failed executions into dead-letter store |
| W8_DLQ_REPLAY | Replays failed items with backoff |
| W8_OPS | Operational tasks (retention purge, health) |
| W15_OUTBOX_WORKER | Reliable outbound message delivery |
| W16_HEALTHZ | Health endpoint for monitoring |
| W17_HEALTH_MONITOR | Active health monitoring with alerts |

## Incident playbooks

- **Worker crash loop**: Check `docker logs n8n-worker`, verify Redis connectivity, check disk space
- **Stuck queue**: `redis-cli LLEN bull:default:wait`, restart worker if growing
- **Redis down**: Worker pauses; restart Redis, verify queue depth recovers
- **Duplicate processing**: Check idempotency keys in DB, verify dedupe node in workflow

## Deliverables

- Queue reliability settings (env vars + compose config)
- Verification: send same event twice, confirm single DB write
- Incident runbook update if topology changes
