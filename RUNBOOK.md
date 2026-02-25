# RUNBOOK — RESTO BOT

## Deploy (standard)
1) Preflight checks
2) Backup DB
3) Apply compose changes
4) Run smoke tests
5) Observe logs + queue + errors for 5–10 minutes

## Rollback (standard)
1) Revert compose/config to last known good
2) Restart previous containers
3) Re-run smoke tests
4) Confirm logs stabilize

## Incidents
- Gateway down
- TLS/Traefik routing issues
- n8n queue backlog
- Redis unavailable
- DB connection failures

(Use `.claude/skills/12_incident_response_oncall` for detailed playbooks.)
