#!/usr/bin/env bash
set -euo pipefail

# P1-DB-002 — quick EXPLAIN ANALYZE bundle to validate index usage.
# Requires: psql

: "${DATABASE_URL:?Missing DATABASE_URL}"

# Optional selectors
: "${CONVERSATION_KEY:=demo_conversation}"
: "${EVENT_TYPE:=AUTH_DENY}"
: "${STATUS:=PENDING}"

echo "== db_explain.sh =="
echo "DATABASE_URL set (hidden)"
echo "CONVERSATION_KEY=$CONVERSATION_KEY"
echo "EVENT_TYPE=$EVENT_TYPE"
echo

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
\timing on

-- 1) inbound_messages: window query by conversation_key / received_at
\echo '--- EXPLAIN inbound_messages (conversation_key + received_at)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, conversation_key, msg_id, channel, received_at
FROM public.inbound_messages
WHERE conversation_key = :'CONVERSATION_KEY'
  AND received_at > (now() - interval '7 days')
ORDER BY received_at DESC
LIMIT 50;

-- 2) security_events: filter by event_type + created_at
\echo '--- EXPLAIN security_events (event_type + created_at)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, tenant_id, restaurant_id, conversation_key, event_type, created_at
FROM public.security_events
WHERE event_type = :'EVENT_TYPE'::text
  AND created_at > (now() - interval '30 days')
ORDER BY created_at DESC
LIMIT 100;

-- 3) outbound_messages: pending/retry due by next_retry_at (representative of W8_OPS picker)
\echo '--- EXPLAIN outbound_messages (status + next_retry_at)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT outbound_id
FROM public.outbound_messages
WHERE status IN ('PENDING','RETRY')
  AND next_retry_at <= now()
ORDER BY next_retry_at ASC
LIMIT 20;

-- 4) outbound_messages: purge path (status SENT + sent_at)
\echo '--- EXPLAIN outbound_messages purge (SENT + sent_at)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT outbound_id
FROM public.outbound_messages
WHERE status='SENT'
  AND sent_at IS NOT NULL
  AND sent_at < (now() - interval '30 days')
ORDER BY sent_at ASC
LIMIT 200;

SQL

echo
echo "Tip: look for Index Scan / Bitmap Index Scan on the indexes added by P1-DB-002."
