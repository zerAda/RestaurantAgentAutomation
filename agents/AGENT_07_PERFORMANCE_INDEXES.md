# AGENT 07 — Performance Optimization Indexes (P0-PERF-01)

## Mission
Add missing database indexes identified in the audit to optimize query performance.

## Priority
**P0 - MEDIUM** - Required for production scale (Ramadan peaks).

## Problem Statement
- Quarantine lookups missing composite index
- Outbox picking missing optimized index
- Security events time queries slow
- Support tickets ops queries unoptimized

## Solution
Add targeted indexes for hot query paths identified in audit.

## Files Modified
- `db/migrations/2026-01-23_p0_perf_indexes.sql`

## Implementation

### Migration SQL
```sql
-- Already provided in audit PERFORMANCE_OPTIMIZATION.sql
-- This agent packages it as a proper migration

BEGIN;

-- Quarantine lookup optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_quarantine_conv_active_exp
  ON conversation_quarantine (conversation_key, active, expires_at);

-- Outbox due picking optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_outbox_status_due
  ON outbound_messages (status, next_retry_at, created_at);

-- Security events burst queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_security_events_time
  ON security_events (created_at DESC);

-- Support tickets ops console
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_support_tickets_status_time
  ON support_tickets (tenant_id, restaurant_id, status, created_at DESC);

-- Token usage log (from Agent 02)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_token_usage_hash
  ON token_usage_log (token_hash, created_at DESC);

-- Admin audit log (from Agent 04)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_admin_audit_time
  ON admin_wa_audit_log (created_at DESC);

COMMIT;
```

### Maintenance Schedule
```sql
-- Run during low-traffic windows (2-5 AM local time)
VACUUM (ANALYZE) inbound_messages;
VACUUM (ANALYZE) outbound_messages;
VACUUM (ANALYZE) security_events;
VACUUM (ANALYZE) conversation_quarantine;
```

## Rollback
```sql
DROP INDEX IF EXISTS idx_quarantine_conv_active_exp;
DROP INDEX IF EXISTS idx_outbox_status_due;
DROP INDEX IF EXISTS idx_security_events_time;
DROP INDEX IF EXISTS idx_support_tickets_status_time;
```

## Validation
```sql
-- Verify indexes exist
SELECT indexname, tablename 
FROM pg_indexes 
WHERE schemaname = 'public' 
  AND indexname LIKE 'idx_%';

-- Check index usage
SELECT 
  schemaname, tablename, indexname, 
  idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

## Validation Checklist
- [ ] All indexes created successfully
- [ ] EXPLAIN shows index usage for target queries
- [ ] No significant increase in write latency
- [ ] Table bloat within acceptable range
