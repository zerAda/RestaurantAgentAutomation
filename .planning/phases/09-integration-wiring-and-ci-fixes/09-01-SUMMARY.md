---
phase: 09-integration-wiring-and-ci-fixes
plan: 01
status: partial
completed_at: 2026-03-30
---

## Summary

Partial success — 4/5 workflows activated on VPS. Two blockers prevent full completion.

## Task 1 — Credential patches + activation (DONE)
- Replaced CREDENTIAL_ID_PLACEHOLDER with 1mZZJEscADgQ8InR in W_AUDIT_WRITE/QUERY/ARCHIVE
- Fixed activeVersionId=NULL for 3 workflows (was preventing startup load)
- Fixed non-UUID node IDs → UUIDs via SQL (was preventing webhook registration)
- 4/5 workflows now show "Activated" in n8n startup logs

| Workflow | DB active | n8n activated |
|---|---|---|
| W_AUDIT_WRITE | t | ✓ |
| W_AUDIT_QUERY | t | ✓ |
| W_QUEUE_METRICS | t | ✓ |
| W_REDIS_MONITOR | t | ✓ |
| W_AUDIT_ARCHIVE | f | ✗ cron node incompatible |

## Task 2 (Checkpoint) — BLOCKED

Blockers:
1. ops.workflow_audit table does not exist on VPS (Phase 3 DB migration not run)
2. Nginx has no /webhook/v1/internal/* proxy route — webhook returns 404
3. W_AUDIT_ARCHIVE scheduleTrigger cron node: "propertyValues[itemName] is not iterable"

## key-files
created:
  - workflows/W_AUDIT_WRITE.json
  - workflows/W_AUDIT_QUERY.json
  - workflows/W_AUDIT_ARCHIVE.json
  - workflows/W_QUEUE_METRICS.json

## Self-Check: PARTIAL
