# Redis Setup for Resto Bot

## Overview

Redis is **REQUIRED** for production deployments. It provides:
- **Idempotence/Dedupe** (`ralphe:dedupe:*`) - Prevent duplicate message processing
- **Rate Limiting** (`ralphe:rl:*`) - Per-conversation rate limiting
- **Outbox Queue** (`ralphe:outbox:*`) - Reliable message delivery
- **Dead Letter Queue** (`ralphe:dlq`) - Failed message handling

## Redis Key Schema

| Key Pattern | Purpose | TTL |
|-------------|---------|-----|
| `ralphe:dedupe:{channel}:{msg_id}` | Message deduplication | 24h (DEDUPE_TTL_SEC) |
| `ralphe:rl:{conversation_key}` | Rate limit counter | 30s sliding window |
| `ralphe:outbox:{msg_id}` | Pending outbound message | 7d (OUTBOX_REDIS_TTL_SEC) |
| `ralphe:dlq` | Dead letter queue (LIST) | No expiry |

## Configuration

### 1. Environment Variables

Add to your `.env`:

```bash
# Redis connection
REDIS_URL=redis://redis:6379

# Deduplication TTL (seconds) - default 24 hours
DEDUPE_TTL_SEC=86400

# Rate limit per 30 seconds per conversation
RL_MAX_PER_30S=6

# Outbox message TTL (seconds) - default 7 days
OUTBOX_REDIS_TTL_SEC=604800

# DLQ alert threshold
DLQ_ALERT_THRESHOLD=10
```

### 2. n8n Redis Credential

1. Open n8n UI (https://console.yourdomain.com)
2. Go to **Credentials** > **New Credential**
3. Select **Redis**
4. Configure:
   - **Host**: `redis` (or your Redis host)
   - **Port**: `6379`
   - **Database**: `0`
   - **Password**: (leave empty if no auth)
5. Save as **"Redis"**
6. Note the credential ID (visible in URL when editing)

### 3. Update Workflow Credentials

After creating the Redis credential, update the workflow files to use your credential ID.

The workflows (W1, W2, W3) contain Redis nodes with placeholder credential references. You'll need to either:

**Option A:** Import workflows and manually link the Redis credential in n8n UI

**Option B:** Update the JSON files before import:
```bash
# Replace placeholder with your credential ID
sed -i 's/REDIS_CREDENTIAL_ID/your-actual-id/g' workflows/W*.json
```

## Docker Compose

Redis is already included in the production docker-compose:

```yaml
redis:
  image: redis:7-alpine
  restart: unless-stopped
  volumes:
    - redis_data:/data
  command: redis-server --appendonly yes
  healthcheck:
    test: ["CMD", "redis-cli", "ping"]
    interval: 10s
    timeout: 5s
    retries: 5
```

## Verification

Test Redis connectivity:

```bash
# From host
docker exec -it redis redis-cli ping
# Should return: PONG

# Test dedupe key
docker exec -it redis redis-cli SET ralphe:dedupe:test:msg123 1 NX EX 60
# Should return: OK (first time) or (nil) (if exists)
```

## Monitoring

Monitor Redis for operational issues:

```bash
# Memory usage
docker exec -it redis redis-cli INFO memory

# Key count by pattern
docker exec -it redis redis-cli --scan --pattern 'ralphe:dedupe:*' | wc -l

# DLQ length
docker exec -it redis redis-cli LLEN ralphe:dlq
```

## Fallback Mode

If Redis is unavailable, the system falls back to PostgreSQL for idempotence (slower but functional). This is logged as a warning in the workflow execution.

---

*Last updated: 2026-01-29*
