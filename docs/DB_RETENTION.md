# DB Retention (P1-DB-002)

## Goals

High‑churn tables must not grow unbounded. This project uses a **safe, parametric purge** executed by **W8_OPS → “Retention Purge”**.

Tables covered:

- `public.inbound_messages` (timestamp: `received_at`)
- `public.security_events` (timestamp: `created_at`)
- `public.outbound_messages` (purge SENT rows by `sent_at`)
- `public.workflow_errors` (timestamp: `created_at`)

All executions are audited in `ops.retention_runs`.

## Environment variables

| Variable | Default | Meaning |
|---|---:|---|
| `RETENTION_DAYS_INBOUND` | 30 | Keep last N days in `inbound_messages` |
| `RETENTION_DAYS_SECURITY` | 90 | Keep last N days in `security_events` |
| `RETENTION_DAYS_OUTBOX_SENT` | 30 | Keep last N days of SENT rows in `outbound_messages` |
| `RETENTION_DAYS_WORKFLOW_ERRORS` | 30 | Keep last N days in `workflow_errors` |
| `RETENTION_BATCH_SIZE` | 5000 | Max rows deleted per batch |
| `RETENTION_MAX_ITERATIONS` | 200 | Safety cap per table per run |
| `RETENTION_DRY_RUN` | false | If true, counts rows but does not delete |

## How it works (safe purge)

The migration `2026-01-22_p1_db_indexes_retention.sql` adds:

- `ops.retention_runs` audit table
- `ops.purge_table_batch(table, cutoff, batch_size, dry_run)` generic batched delete
- `ops.purge_outbound_sent_batch(cutoff, batch_size, dry_run)` specialized purge for outbox SENT rows
- indexes to keep the purge **index‑friendly**

The workflow executes batches until:

- a batch deletes **less** than `RETENTION_BATCH_SIZE`, or
- `RETENTION_MAX_ITERATIONS` is reached (hard stop)

## Operational notes

### Recommended schedule

Run daily during low traffic (e.g., **03:30 local time**).

### Vacuum / bloat

Deletes can create bloat. The migration applies table‑level autovacuum hints (lower scale factors) for the high‑churn tables. Monitor vacuum activity and adjust if needed.

### Dry‑run

Set `RETENTION_DRY_RUN=true` to validate cutoffs and expected deletion volumes without deleting.

## Manual run

You can run one batch manually:

```sql
SELECT * FROM ops.purge_table_batch('public.security_events', now() - interval '90 days', 5000, false);
SELECT * FROM ops.purge_outbound_sent_batch(now() - interval '30 days', 5000, false);
```

## Rollback

See `ROLLBACK.md`.
