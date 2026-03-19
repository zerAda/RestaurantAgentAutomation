# RUNBOOK — RESTO BOT

---

## CD Workflows

Two paths depending on what changed:

### Path A — Config/Dockerfile change (quick push from local)

Use when: Dockerfile, nginx.conf, compose file, scripts, or other non-image files changed.

```bash
# From project/ directory on local machine:

# 1. Sync files only
./scripts/vps-sync.sh --sync

# 2a. Rebuild + restart a service (e.g., cms)
./scripts/vps-sync.sh --sync cms

# 2b. Restart only (no rebuild, e.g. nginx config change)
./scripts/vps-sync.sh --sync --restart gateway

# 2c. Full rebuild ignoring Docker cache
./scripts/vps-sync.sh --sync cms --no-cache
```

### Path B — Code change (via CI/CD + GHCR)

Use when: source code changed and CI has built the image.

```bash
# Push to main → CI builds → GHCR → CD deploys automatically
# OR pull a specific tag manually:
./scripts/vps-sync.sh --pull cms latest
./scripts/vps-sync.sh --pull cms sha-abc1234
```

### Path C — VPS-side only (SSH in and rebuild directly)

```bash
ssh deploy@72.60.190.192
bash /opt/resto/rebuild.sh cms             # rebuild + restart
bash /opt/resto/rebuild.sh cms --no-cache  # full rebuild
bash /opt/resto/rebuild.sh gateway         # restart only (image service)
bash /opt/resto/rebuild.sh all             # restart all services
```

---

## Deploy (standard via CI/CD)
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

## Smoke Tests

```bash
# On VPS:
bash /opt/resto/current/scripts/smoke-cms-routes.sh
bash /opt/resto/current/scripts/smoke-post-rebuild.sh
```

## Incidents
- Gateway down
- TLS/Traefik routing issues
- n8n queue backlog
- Redis unavailable
- DB connection failures

(Use `.claude/skills/12_incident_response_oncall` for detailed playbooks.)
