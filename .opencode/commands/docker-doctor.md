---
description: Diagnose docker/compose state, conflicts, healthchecks and runtime failures
agent: platform-sre
subtask: true
---

Diagnose docker/compose state, conflicts, healthchecks and likely runtime failures.

You are the **platform-sre** role. Diagnose, don't fix (unless trivial).

Workflow:

1. Check container state:
   - Run: `docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>&1`
   - Run: `docker compose ps 2>&1`

2. Check for problems:
   - Unhealthy containers (status contains "unhealthy")
   - Restart loops (high restart count)
   - Port conflicts
   - Missing containers (expected 12)
   - Containers in "starting" state too long

3. Check compose config:
   - Run: `docker compose -f docker-compose.hostinger.prod.yml config --quiet 2>&1`
   - Look for env var warnings, missing files, syntax errors

4. Check disk and resources:
   - Run: `df -h / 2>/dev/null`
   - Run: `docker system df 2>/dev/null`

5. Check recent logs for errors:
   - Run: `docker compose logs --tail=20 --no-color 2>&1 | grep -i "error\|fatal\|panic\|crash" | head -20`

6. Produce diagnosis:

   ## Container Health
   | Service | Status | Issues |
   |---------|--------|--------|

   ## Compose Config
   Valid / Invalid + details

   ## Resource State
   Disk, images, volumes

   ## Recent Errors
   Top issues from logs

   ## Verdict
   - Severity: OK / WARNING / CRITICAL
   - Root cause (if identifiable)
   - Fastest safe fix

7. Write findings to `vault/40-Runbooks/Docker Doctor.md`
8. Update active NID if relevant
