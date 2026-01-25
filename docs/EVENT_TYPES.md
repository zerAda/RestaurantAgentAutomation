# Event Types (P1-DB-003)

## Why

`public.security_events.event_type` is enforced by a Postgres **ENUM** to prevent accidental drift (typos, inconsistent naming).

The allowed values are also listed in `ops.security_event_types` (reference / documentation table).

## Allowed `security_events.event_type`

| Code | Description |
|---|---|
| `AUTH_DENY` | Auth token invalid / access denied |
| `AUDIO_URL_BLOCKED` | Voice URL rejected by security gate |
| `RETENTION_RUN` | Retention purge job execution log |
| `CONTRACT_VALIDATION_FAILED` | Inbound payload rejected by JSON Schema validation |
| `SLO_BREACH` | SLO threshold breached (queue/outbox) |

## Adding a new event type

1. Add the new code to `ops.security_event_types` (migration).
2. Add the value to the enum `security_event_type_enum` (same migration).
3. Update this doc.

This must be done via a migration to keep environments consistent.

## Rollback

See `ROLLBACK.md`.