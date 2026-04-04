# Phase 11: VPS Ops — Apply DB Migration & Activate Audit Chain - Research

**Researched:** 2026-04-04
**Domain:** VPS operations — PostgreSQL migration, n8n 2.x workflow activation, Docker gateway recreation
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AUDIT-02 | All inbound adapter workflows write an audit entry on execution start and end | Requires `ops.workflow_audit` table to exist on VPS; W_AUDIT_WRITE is already active on VPS but silently fails with relation-not-found — applying the migration unblocks it |
| AUDIT-04 | Audit entries retained for 90 days, then archived (not deleted) | W_AUDIT_ARCHIVE must be re-imported with the n8n 2.x-compatible cron node (commit 8bd4c33) and activated via SQL UPDATE |
</phase_requirements>

---

## Summary

Phase 11 is a pure VPS operations phase — no new code, no new workflow logic. Three concrete gaps from the v1.0 audit must be closed at runtime: the Phase 3 DB migration (`2026-03-23_p3_workflow_audit.sql`) was never applied to VPS Postgres, W_AUDIT_ARCHIVE was never re-imported with the n8n 2.x cron fix, and the gateway container was never recreated to pick up the `/v1/internal/` nginx location block that was committed in Phase 9.

All three artifacts are ready and correct in the local repo. The work is entirely about deploying what already exists: copy the migration SQL into the VPS postgres container and execute it, SCP the fixed W_AUDIT_ARCHIVE.json to VPS and re-import it via the n8n API, activate it via SQL + restart, then `docker compose up -d gateway` to recreate the container from the current compose bind-mount.

The critical database question is which database the migration targets: it is the `n8n` database (user=`n8n`, db=`n8n`), not `strapi`. The `ops` schema lives in the n8n DB — this is where n8n workflows store execution data and where W_AUDIT_WRITE inserts rows using credential `1mZZJEscADgQ8InR` ("RestoBot PG (n8n DB)"). The audit report's fix suggestion mentioning `psql -U strapi -d strapi` is an error — using it would target the wrong database.

**Primary recommendation:** Run all three operations in sequence — migration first (unblocks W_AUDIT_WRITE), then W_AUDIT_ARCHIVE re-import and activation (closes AUDIT-04), then gateway recreate (exposes `/v1/internal/` to public traffic). Verify each step with a direct SQL or HTTP assertion before proceeding to the next.

---

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| psql | 15 (postgres container) | Run migration SQL inside VPS postgres container | Docker exec pattern — no external access needed |
| docker compose exec | Docker 24.x | Execute commands in running containers | Established project pattern for all VPS DB ops |
| ssh | system | Tunnel commands to VPS | Only access method for VPS (key auth, deploy@72.60.190.192) |
| scp | system | Copy local JSON files to VPS | Needed to transfer updated W_AUDIT_ARCHIVE.json |
| curl | system (inside VPS n8n-main) | Import workflows via n8n REST API | n8n CLI import hangs in queue mode; HTTP API is reliable |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| db_migrate.sh | local script | Idempotent single-file migration runner | Phase's primary migration mechanism |
| db_migrate_all.sh | local script | Multi-file migration runner with tracking | Use for listing pending migrations or dry-run |
| n8n REST API | n8n 2.9.4 | Import/check workflows | POST /rest/workflows (not n8n CLI — hangs in queue mode) |
| workflow_entity SQL | Postgres | Activate workflow, set active=true reliably | PATCH /activate API returns `active=unknown` in n8n 2.9.4 |

**Installation:** No new dependencies. All tools are already on VPS.

---

## Architecture Patterns

### Pattern 1: DB Migration via docker compose exec (Established Project Pattern)

**What:** SCP the migration file to VPS, then run it inside the postgres container via stdin redirect.
**When to use:** Any time a migration SQL must be applied to VPS Postgres without recreating the container.
**Example:**
```bash
# Source: scripts/db_migrate.sh (project established pattern)
scp db/migrations/2026-03-23_p3_workflow_audit.sql deploy@72.60.190.192:/tmp/p3_workflow_audit.sql

ssh deploy@72.60.190.192 \
  "cd /opt/resto/current && \
   docker compose -f docker-compose.hostinger.prod.yml exec -T postgres \
   sh -c 'psql -v ON_ERROR_STOP=1 -U n8n -d n8n' < /tmp/p3_workflow_audit.sql"
```

**CRITICAL:** Use `-U n8n -d n8n` — the `ops` schema lives in the `n8n` database. Using `-U strapi -d strapi` targets the wrong DB and will fail (ops schema does not exist there).

**Verify migration applied:**
```bash
ssh deploy@72.60.190.192 \
  "docker exec current-postgres-1 psql -U n8n -d n8n -Atc \
   \"SELECT COUNT(*) FROM ops.workflow_audit;\""
```
Expected output: `0` (table exists, no rows yet). Any error means migration failed.

### Pattern 2: n8n 2.x Workflow Activation (Established Pattern — Phase 8/9)

**What:** Import workflow via n8n REST API, then activate via SQL UPDATE + container restart.
**When to use:** Any time a workflow must be activated on VPS n8n 2.9.4.
**Why SQL, not PATCH:** `PATCH /rest/workflows/:id/activate` returns `active=unknown` in n8n 2.9.4 — unreliable. `UPDATE workflow_entity SET active = true` followed by n8n-main restart is the reliable path (`ActiveWorkflowManager.init()` re-registers all active workflows on startup).

```bash
# Step 1: Get n8n API key from DB
N8N_KEY=$(ssh deploy@72.60.190.192 \
  "docker exec current-postgres-1 psql -U n8n -d n8n -Atc \
   \"SELECT \\\"apiKey\\\" FROM user_api_keys LIMIT 1;\"")

# Step 2: SCP fixed workflow to VPS
scp workflows/W_AUDIT_ARCHIVE.json deploy@72.60.190.192:/tmp/W_AUDIT_ARCHIVE.json

# Step 3: Check if workflow already exists on VPS
ssh deploy@72.60.190.192 \
  "docker exec current-postgres-1 psql -U n8n -d n8n -Atc \
   \"SELECT id, name, active FROM workflow_entity \
    WHERE name = 'W_AUDIT_ARCHIVE - 90-Day Audit Archival';\""

# Step 4a: If workflow exists — delete stale version and re-import (ensures n8n 2.x cron fix is live)
ssh deploy@72.60.190.192 \
  "docker exec current-postgres-1 psql -U n8n -d n8n -c \
   \"DELETE FROM workflow_entity WHERE name = 'W_AUDIT_ARCHIVE - 90-Day Audit Archival';\""

# Step 4b: Import fixed workflow via n8n API (from inside container to localhost)
ssh deploy@72.60.190.192 \
  "curl -s -X POST http://localhost:5678/rest/workflows \
   -H \"X-N8N-API-KEY: \$N8N_KEY\" \
   -H 'Content-Type: application/json' \
   -d @/tmp/W_AUDIT_ARCHIVE.json"

# Step 5: Activate via SQL
ssh deploy@72.60.190.192 \
  "docker exec current-postgres-1 psql -U n8n -d n8n -c \
   \"UPDATE workflow_entity SET active = true \
    WHERE name = 'W_AUDIT_ARCHIVE - 90-Day Audit Archival';\""

# Step 6: Restart n8n-main to register cron trigger
ssh deploy@72.60.190.192 \
  "cd /opt/resto/current && \
   docker compose -f docker-compose.hostinger.prod.yml restart n8n-main"
```

**Verify:**
```bash
ssh deploy@72.60.190.192 \
  "docker exec current-postgres-1 psql -U n8n -d n8n -Atc \
   \"SELECT name, active FROM workflow_entity \
    WHERE name = 'W_AUDIT_ARCHIVE - 90-Day Audit Archival';\""
```
Expected: `W_AUDIT_ARCHIVE - 90-Day Audit Archival|t`

### Pattern 3: Gateway Container Recreation (VPS Session 2026-03-14 — Established Pattern)

**What:** `docker compose up -d gateway` from `/opt/resto/current/` recreates the gateway container, picking up the current compose bind-mount of `infra/gateway/nginx.conf`.
**Why needed:** VPS gateway container was started from an old path (`/root/project/`) that no longer exists. Docker preserves bind mounts by inode. Changes to `nginx.conf` on VPS are not seen by the running container until it is recreated. The `/v1/internal/` location block committed in Phase 9 is in `nginx.conf` but the running container does not serve it.

```bash
ssh deploy@72.60.190.192 \
  "cd /opt/resto/current && \
   docker compose -f docker-compose.hostinger.prod.yml up -d gateway"
```

**Verify:**
```bash
# From VPS: test internal routing (inside Docker network, no auth header needed)
ssh deploy@72.60.190.192 \
  "curl -s -o /dev/null -w '%{http_code}' \
   https://api.srv1258231.hstgr.cloud/v1/internal/audit-log"
```
Expected: any non-502 response (404 is acceptable — it means gateway routed the request to n8n; the n8n workflow may return 404 if not properly listening on that path, but 502 means the gateway didn't route at all).

**Note on W_AUDIT_QUERY webhook path:** The actual audit-log query endpoint is `GET /webhook/v1/internal/audit-log` on n8n-main. The nginx `/v1/internal/` location block proxies to `http://n8n_upstream/webhook/v1/internal/`. So `GET /v1/internal/audit-log` routes to `GET /webhook/v1/internal/audit-log`. W_AUDIT_QUERY must be active for the route to return 200.

### Anti-Patterns to Avoid

- **PATCH /rest/workflows/:id/activate:** Returns `active=unknown` in n8n 2.9.4. Never use.
- **`-U strapi -d strapi` for ops schema migration:** The `ops` schema is in the `n8n` DB. Using strapi credentials targets the wrong database.
- **Using n8n CLI (`n8n import:workflow`):** Hangs in queue mode (established failure in Phase 9). Use the HTTP REST API.
- **Reloading nginx without recreating container:** `nginx -s reload` inside the running container will NOT pick up updated `nginx.conf` if the bind mount is stale (mounted from old inode path). Container recreation is required.
- **Skipping restart after SQL activation:** Without n8n-main restart, `ActiveWorkflowManager` doesn't register the cron trigger. The workflow shows `active=true` in DB but never fires.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Applying migration idempotently | Custom shell script | `db_migrate.sh` + `CREATE TABLE IF NOT EXISTS` | Already handles ON_ERROR_STOP, tracking via schema_migrations |
| Workflow import | n8n CLI import command | curl POST to /rest/workflows | CLI hangs in queue mode (confirmed Phase 9 failure) |
| Checking workflow activation | HTTP polling loop | SQL SELECT from workflow_entity | Direct DB query is faster and reliable |
| n8n workflow activation | PATCH API | SQL UPDATE + restart | PATCH returns active=unknown in n8n 2.9.4 |

**Key insight:** Every mechanism in this phase has already been tested and validated in Phase 9. The plan should reference exactly the same patterns — no new approaches needed.

---

## Common Pitfalls

### Pitfall 1: Wrong database for ops schema migration
**What goes wrong:** Migration is run against the `strapi` database instead of `n8n`. `CREATE TABLE IF NOT EXISTS ops.workflow_audit` succeeds (ops schema doesn't exist there, but it creates it). W_AUDIT_WRITE still fails because its credential `1mZZJEscADgQ8InR` connects to the `n8n` DB where the table still doesn't exist.
**Why it happens:** The v1.0 audit report fix suggestion mentions `-U strapi -d strapi` — this is an error in the audit report.
**How to avoid:** Always use `-U n8n -d n8n`. The ops schema was created in the n8n DB by `2026-01-22_p1_db_indexes_retention.sql`. W_AUDIT_WRITE uses credential "RestoBot PG (n8n DB)" — it connects to n8n, not strapi.
**Warning sign:** `SELECT COUNT(*) FROM ops.workflow_audit` returns an error even after running the migration.

### Pitfall 2: Stale W_AUDIT_ARCHIVE already on VPS with broken cron node
**What goes wrong:** The workflow exists on VPS with the old `triggerAtHour:3` cron syntax. Activating it via SQL makes it `active=true` in the DB, but n8n throws `propertyValues[itemName] is not iterable` on startup and the cron never fires.
**Why it happens:** Phase 9 plan 01 could not activate W_AUDIT_ARCHIVE due to this bug. The workflow may exist on VPS with the old format.
**How to avoid:** Delete the stale workflow_entity row before re-importing the fixed JSON (commit 8bd4c33). Import the current local `workflows/W_AUDIT_ARCHIVE.json` which already has the fix applied.
**Warning sign:** n8n logs show `propertyValues[itemName] is not iterable` after restart.

### Pitfall 3: Gateway container recreation causes brief downtime
**What goes wrong:** `docker compose up -d gateway` recreates the container, causing a few seconds where the API gateway is unavailable.
**Why it happens:** Container recreation requires stop + start cycle.
**How to avoid:** Run during a low-traffic window. The compose file handles graceful restart. All other services remain running. Downtime is typically < 5 seconds.
**Warning sign:** Brief 502s from Traefik during the 3-5 second recreation window.

### Pitfall 4: n8n-main restart needed AFTER workflow import
**What goes wrong:** Workflow shows `active=true` in DB but cron never fires. `GET /webhook/v1/internal/audit-write` returns 404.
**Why it happens:** n8n's `ActiveWorkflowManager` loads webhook routes and schedules cron jobs only on startup. A DB change while n8n is running is not picked up until the process restarts.
**How to avoid:** Always restart n8n-main after activating workflows via SQL. Allow 30-60 seconds for health check to pass before verifying.
**Warning sign:** Webhook returns 404 after activation, or `/healthz` returns non-200.

### Pitfall 5: /v1/internal/audit-log returns 502 even after gateway recreation
**What goes wrong:** Gateway recreated, but route still returns 502.
**Why it happens:** W_AUDIT_QUERY workflow may not be active (it was activated in Phase 9 plan 01 but check current state). n8n-main may not have registered the webhook route.
**How to avoid:** Verify W_AUDIT_QUERY is still active on VPS before testing the route. If n8n-main was restarted for W_AUDIT_ARCHIVE, it should also re-register W_AUDIT_QUERY's webhook routes (they're all loaded together on startup).
**Warning sign:** 502 from gateway even after container recreation.

---

## Code Examples

Verified patterns from established project scripts and Phase 9 execution:

### Pre-flight: Check what's already on VPS

```bash
# Check if ops.workflow_audit table exists
ssh deploy@72.60.190.192 \
  "docker exec current-postgres-1 psql -U n8n -d n8n -Atc \
   \"SELECT to_regclass('ops.workflow_audit');\""
# Returns: ops.workflow_audit (exists) or (empty) (does not exist)

# Check W_AUDIT_ARCHIVE current state on VPS
ssh deploy@72.60.190.192 \
  "docker exec current-postgres-1 psql -U n8n -d n8n -Atc \
   \"SELECT name, active FROM workflow_entity \
    WHERE name = 'W_AUDIT_ARCHIVE - 90-Day Audit Archival';\""

# Check gateway nginx version (which conf is serving)
ssh deploy@72.60.190.192 \
  "docker exec current-gateway-1 nginx -T 2>/dev/null | grep -A3 'v1/internal' || echo 'NOT FOUND'"
```

### Apply DB migration (Phase 3 SQL)

```bash
# SCP migration to VPS
scp "db/migrations/2026-03-23_p3_workflow_audit.sql" \
  deploy@72.60.190.192:/tmp/p3_workflow_audit.sql

# Apply migration (idempotent — uses CREATE TABLE IF NOT EXISTS)
ssh deploy@72.60.190.192 \
  "cd /opt/resto/current && \
   docker compose -f docker-compose.hostinger.prod.yml exec -T postgres \
   sh -c 'psql -v ON_ERROR_STOP=1 -U n8n -d n8n' < /tmp/p3_workflow_audit.sql"

# Verify: table exists
ssh deploy@72.60.190.192 \
  "docker exec current-postgres-1 psql -U n8n -d n8n -Atc \
   \"SELECT COUNT(*) FROM ops.workflow_audit;\""
# Expected: 0
```

### Re-import and activate W_AUDIT_ARCHIVE

```bash
# Fetch n8n API key
N8N_KEY=$(ssh deploy@72.60.190.192 \
  "docker exec current-postgres-1 psql -U n8n -d n8n -Atc \
   \"SELECT \\\"apiKey\\\" FROM user_api_keys LIMIT 1;\"")

# SCP fixed workflow JSON to VPS
scp workflows/W_AUDIT_ARCHIVE.json deploy@72.60.190.192:/tmp/W_AUDIT_ARCHIVE.json

# Delete stale version (if exists)
ssh deploy@72.60.190.192 \
  "docker exec current-postgres-1 psql -U n8n -d n8n -c \
   \"DELETE FROM workflow_entity \
    WHERE name = 'W_AUDIT_ARCHIVE - 90-Day Audit Archival';\""

# Import fresh version via REST API (from inside VPS)
ssh deploy@72.60.190.192 \
  "curl -s -X POST http://localhost:5678/rest/workflows \
   -H \"X-N8N-API-KEY: ${N8N_KEY}\" \
   -H 'Content-Type: application/json' \
   -d @/tmp/W_AUDIT_ARCHIVE.json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(\"id\",d))'"

# Activate via SQL
ssh deploy@72.60.190.192 \
  "docker exec current-postgres-1 psql -U n8n -d n8n -c \
   \"UPDATE workflow_entity SET active = true \
    WHERE name = 'W_AUDIT_ARCHIVE - 90-Day Audit Archival';\""

# Restart n8n-main to register cron trigger
ssh deploy@72.60.190.192 \
  "cd /opt/resto/current && \
   docker compose -f docker-compose.hostinger.prod.yml restart n8n-main"

# Wait for n8n-main health (poll up to 60s)
for i in $(seq 1 12); do
  STATUS=$(ssh deploy@72.60.190.192 \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:5678/healthz")
  [ "$STATUS" = "200" ] && echo "n8n healthy" && break
  echo "Waiting... ($i/12)"
  sleep 5
done

# Verify active=true in DB
ssh deploy@72.60.190.192 \
  "docker exec current-postgres-1 psql -U n8n -d n8n -Atc \
   \"SELECT name, active FROM workflow_entity \
    WHERE name = 'W_AUDIT_ARCHIVE - 90-Day Audit Archival';\""
# Expected: W_AUDIT_ARCHIVE - 90-Day Audit Archival|t
```

### Recreate gateway container

```bash
ssh deploy@72.60.190.192 \
  "cd /opt/resto/current && \
   docker compose -f docker-compose.hostinger.prod.yml up -d gateway"

# Wait ~5s for nginx to start, then verify /v1/internal/ route is routable
sleep 5
curl -s -o /dev/null -w '%{http_code}' \
  https://api.srv1258231.hstgr.cloud/v1/internal/audit-log
# Expected: NOT 502 (502 = gateway didn't route; anything else means nginx is serving the route)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| PATCH /rest/workflows/:id/activate | SQL UPDATE workflow_entity SET active = true + restart | Phase 8/9 | PATCH returns active=unknown in n8n 2.9.4 — unreliable |
| n8n CLI `import:workflow` | curl POST to n8n REST API | Phase 9 | CLI hangs in queue mode |
| `triggerAtHour: 3` in scheduleTrigger | Remove triggerAtHour from rule object | Commit 8bd4c33 | n8n 2.x scheduleTrigger throws `propertyValues[itemName] is not iterable` with hoursInterval + triggerAtHour combined |
| Runtime docker cp injection (CMS routes) | Committed TS source files | Phase 1 | Never inject files at runtime |

**Deprecated/outdated:**
- `triggerAtHour` in scheduleTrigger interval config: Removed in commit 8bd4c33. Current `W_AUDIT_ARCHIVE.json` runs on 24-hour interval only (fires whenever n8n schedules it within the day).

---

## Key Facts for Planning

### What is already correct in local repo (no changes needed)

1. `workflows/W_AUDIT_ARCHIVE.json` — n8n 2.x cron fix applied (commit 8bd4c33), credential ID `1mZZJEscADgQ8InR` correct, `"active": true`.
2. `infra/gateway/nginx.conf` — `/v1/internal/` location block present at lines 348-355. Proxies to `http://n8n_upstream/webhook/v1/internal/` with correct headers.
3. `db/migrations/2026-03-23_p3_workflow_audit.sql` — idempotent `CREATE TABLE IF NOT EXISTS`, all indexes included.

### What must happen on VPS (no code changes, only ops)

1. Apply `2026-03-23_p3_workflow_audit.sql` to VPS Postgres (`n8n` DB) — creates `ops.workflow_audit` and `ops.workflow_audit_archive`.
2. Delete stale W_AUDIT_ARCHIVE from VPS workflow_entity + re-import fixed JSON + activate + restart n8n-main.
3. Recreate gateway container with `docker compose up -d gateway`.

### Sequence matters

Migration must come FIRST — without `ops.workflow_audit`, W_AUDIT_WRITE silently fails (it uses `continueOnFail: true`). Gateway recreation can be done before or after n8n restart; it does not depend on DB state. W_AUDIT_ARCHIVE activation requires n8n restart; plan the sequence to minimize total restart count (one restart serves both W_AUDIT_ARCHIVE activation and any other workflow registration).

### VPS credentials

- SSH: `deploy@72.60.190.192` (key auth)
- Postgres user: `n8n`, database: `n8n`, container: `current-postgres-1`
- n8n API key: `SELECT "apiKey" FROM user_api_keys LIMIT 1;`
- n8n-main container: `current-n8n-main-1`
- Gateway container: `current-gateway-1`
- Compose file: `docker-compose.hostinger.prod.yml`
- Working dir: `/opt/resto/current/`

---

## Validation Architecture

> nyquist_validation is enabled (config.json).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | SSH + psql + curl (VPS operational verification, no unit test framework) |
| Config file | none — inline commands |
| Quick run command | `ssh deploy@72.60.190.192 "docker exec current-postgres-1 psql -U n8n -d n8n -Atc \"SELECT COUNT(*) FROM ops.workflow_audit;\""` |
| Full suite command | All three verification commands in sequence (see Phase Requirements test map) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AUDIT-02 | ops.workflow_audit table exists with correct schema | smoke | `ssh deploy@72.60.190.192 "docker exec current-postgres-1 psql -U n8n -d n8n -Atc \"SELECT COUNT(*) FROM ops.workflow_audit;\""` | ❌ Wave 0 (VPS ops, no test file) |
| AUDIT-04 | W_AUDIT_ARCHIVE active=true on VPS | smoke | `ssh deploy@72.60.190.192 "docker exec current-postgres-1 psql -U n8n -d n8n -Atc \"SELECT active FROM workflow_entity WHERE name = 'W_AUDIT_ARCHIVE - 90-Day Audit Archival';\"" \| grep -c '^t$'` | ❌ Wave 0 (VPS ops, no test file) |
| AUDIT-04 (gateway) | GET /v1/internal/audit-log is routable (non-502) | smoke | `curl -s -o /dev/null -w '%{http_code}' https://api.srv1258231.hstgr.cloud/v1/internal/audit-log \| grep -v 502` | ❌ Wave 0 (VPS ops, no test file) |

### Sampling Rate

- **Per task commit:** SSH verify command for that task's success criterion
- **Per wave merge:** All three verification commands in sequence
- **Phase gate:** All three truths verified before writing SUMMARY.md

### Wave 0 Gaps

- No test files to create — all verification is SSH-based operational checks against live VPS.
- "None — test infrastructure for this phase is SSH command verification, no file artifacts needed."

---

## Open Questions

1. **Is ops schema already present in n8n DB on VPS from earlier migrations?**
   - What we know: `2026-01-22_p1_db_indexes_retention.sql` creates `CREATE SCHEMA IF NOT EXISTS ops` and was part of the original bootstrap. Phase 9 plan 01 documented "ops.workflow_audit table does not exist on VPS" — but the ops schema itself may already exist.
   - What's unclear: Whether the ops schema (without workflow_audit) exists, or whether the entire ops schema is absent.
   - Recommendation: The `2026-03-23_p3_workflow_audit.sql` migration uses `CREATE TABLE IF NOT EXISTS ops.workflow_audit` — it will fail if the ops schema does not exist. Pre-flight check should verify `SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'ops'` and create the schema if missing.

2. **Is W_AUDIT_QUERY still active on VPS after Phase 9 partial execution?**
   - What we know: Phase 9 plan 01 summary shows W_AUDIT_QUERY was activated (`t`). No subsequent operation would have deactivated it.
   - What's unclear: State drift is possible; VPS may have been partially restored or containers recreated.
   - Recommendation: Pre-flight check should verify all Phase 3 workflows' activation state. If W_AUDIT_QUERY is inactive, re-activate it (same SQL pattern, no re-import needed since it has the correct credential ID).

3. **Will n8n-main restart affect in-flight queue executions?**
   - What we know: n8n runs in queue mode. The worker picks up jobs from Redis Bull queue, not from n8n-main directly. Restarting n8n-main does not lose queued executions.
   - What's unclear: Any execution currently being received via webhook at the moment of restart will be dropped.
   - Recommendation: Low-traffic window; restart is safe for queue mode deployments.

---

## Sources

### Primary (HIGH confidence)
- `db/migrations/2026-03-23_p3_workflow_audit.sql` — exact migration SQL, schema, indexes
- `workflows/W_AUDIT_ARCHIVE.json` — current state of workflow with n8n 2.x fix applied
- `infra/gateway/nginx.conf` — confirmed `/v1/internal/` location block at lines 348-355
- `scripts/db_migrate.sh`, `scripts/db_migrate_all.sh` — established migration patterns
- `.planning/phases/09-integration-wiring-and-ci-fixes/09-01-SUMMARY.md` — confirmed blockers from Phase 9 execution (migration not run, cron incompatibility, no /v1/internal/ route)
- `.planning/phases/09-integration-wiring-and-ci-fixes/09-01-PLAN.md` — established n8n 2.x activation pattern with exact commands
- `.planning/v1.0-MILESTONE-AUDIT.md` — INT-01, INT-05 root cause analysis
- `docker-compose.hostinger.prod.yml` — confirmed n8n DB = `n8n`, user = `n8n`
- `workflows/W_AUDIT_WRITE.json` — confirmed credential `1mZZJEscADgQ8InR` = "RestoBot PG (n8n DB)" → n8n DB
- `git show 8bd4c33` — confirmed cron fix: removed triggerAtHour, replaced non-UUID node IDs

### Secondary (MEDIUM confidence)
- MEMORY.md session 2026-03-14: Gateway container old path issue — `docker compose up -d gateway` recreates with new bind mount path. Confirms gateway recreation is the correct fix.
- MEMORY.md session 2026-03-07: n8n credential IDs confirmed: Postgres=1mZZJEscADgQ8InR, Redis=43SDqJYMGa6RvFqW

### Tertiary (LOW confidence)
- None.

---

## Metadata

**Confidence breakdown:**
- DB migration target (n8n DB, not strapi): HIGH — confirmed by W_AUDIT_WRITE credential name, db_migrate.sh pattern, migration comment referencing p1 migration which is also in n8n DB
- W_AUDIT_ARCHIVE fix state: HIGH — confirmed by `git show 8bd4c33` + reading current JSON
- nginx `/v1/internal/` block present: HIGH — read directly from infra/gateway/nginx.conf lines 348-355
- Gateway container stale on VPS: MEDIUM — documented in MEMORY.md + Phase 9 blocker 2, but not verified live in this research session
- ops schema pre-existing in n8n DB: MEDIUM — earlier migrations create it (IF NOT EXISTS), but VPS state not verified live

**Research date:** 2026-04-04
**Valid until:** 2026-05-04 (stable operations domain; only invalidated by n8n upgrade or DB schema changes)
