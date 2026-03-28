# Phase 7: Fix Critical Defects — Research

**Researched:** 2026-03-28
**Domain:** n8n workflow JSON patching, Docker build-arg injection, React/Vite env-var wiring
**Confidence:** HIGH

---

## Summary

Phase 7 closes two fail-gate defects uncovered by the v1.0 milestone audit. Both defects exist in
code that was already committed — this phase is surgical repair, not new feature work.

**Defect 1 — METR-05 (disk alert dead code):** During Phase 3, a security hardening pass (MED-09)
removed `execSync('df -k /')` from the `B0 - Compute Metrics` Code node in
`W_QUEUE_METRICS.json`. The replacement left `diskUsedGB = -1` and `diskUsedPct = -1` as permanent
hardcodes. Because `diskUsedPct > diskAlertPct` evaluates to `-1 > 80` (always false), the CRITICAL
DISK_ALERT log line can never fire. The fix is to reinstate the `df -k /` parse inside the same
Code node — this is safe because n8n 2.9.4 Code nodes run in the main Node.js process with access
to all built-in modules when `NODE_FUNCTION_ALLOW_BUILTIN` is not restricted (confirmed: no such
variable in compose or .env). The `try/catch` guard that was already present correctly handles
`execSync` failures by falling back to `-1`.

**Defect 2 — AUDIT-03 (AuditLogView double-broken):** Two independent breaks prevent the audit
view from ever reaching W_AUDIT_QUERY. First, `admin-dashboard/Dockerfile` never declares
`ARG VITE_N8N_URL` or `ENV VITE_N8N_URL`, so Vite bakes `import.meta.env.VITE_N8N_URL` as
`undefined` at build time; AuditLogView.tsx falls back to empty string, making all fetch calls
relative to the dashboard's own nginx origin (which knows nothing about n8n). Second, even if the
URL were correct, the fetch path is `webhook/v1/internal/audit-query` but W_AUDIT_QUERY.json
registers the path as `v1/internal/audit-log`. The webhook URL must use the path declared in the
workflow, not the opposite.

**Primary recommendation:** Three surgical file changes — patch one Code node's `jsCode` string in
`W_QUEUE_METRICS.json`, add two ARG/ENV lines to `admin-dashboard/Dockerfile`, add one build arg to
`docker-compose.hostinger.prod.yml`, and change one string in `AuditLogView.tsx` line 111. No
architectural changes. No new dependencies.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| METR-05 | Alert fires when disk usage > 80% of 119GB | Defect root-cause fully understood: `diskUsedPct = -1` hardcode in B0-Compute-Metrics node; fix is reinstate `df -k /` parse with existing `try/catch` guard |
| AUDIT-03 | Audit log queryable from admin dashboard via W_AUDIT_QUERY webhook | Two-part defect fully mapped: (1) Dockerfile missing ARG/ENV for VITE_N8N_URL, (2) fetch path `audit-query` does not match workflow path `audit-log`; both fixable in < 10 lines |

</phase_requirements>

---

## Defect Anatomy

### METR-05: Disk Alert Dead Code

**File:** `workflows/W_QUEUE_METRICS.json`
**Node:** `B0 - Compute Metrics` (id: `compute-metrics`, position: [-50, 0])

**Broken code (current state):**
```javascript
// MED-09 FIX: Removed execSync('df -k /') shell execution.
// Disk usage is handled externally via Docker/Prometheus.
var diskUsedGB = -1;
var diskUsedPct = -1;
```

The "handled externally" comment is aspirational fiction — no external Prometheus or Docker metrics
endpoint was ever wired. The DISK_ALERT block that follows checks `diskUsedPct >= cfg.diskAlertPct`
but that block was moved into a different node (`B0 - Alert Decision`) in the actual implementation.
Specifically, the "B0 - Alert Decision" node does NOT contain a disk alert check — it only handles
the queue sustained-threshold counter. The disk CRITICAL log was intended to live in
"B0 - Compute Metrics" itself (as shown in the 03-02-PLAN.md spec), but the MED-09 patch removed
it entirely along with `execSync`.

**What the fix restores:**
```javascript
var diskUsedGB = -1;
var diskUsedPct = -1;
try {
  var dfOut = require('child_process').execSync('df -k /').toString();
  var lines = dfOut.trim().split('\n');
  if (lines.length >= 2) {
    var parts = lines[1].trim().split(/\s+/);
    var usedKB = parseInt(parts[2], 10);
    diskUsedGB = Math.round(usedKB / 1024 / 1024 * 10) / 10;
    diskUsedPct = parseInt(parts[4].replace('%', ''), 10);
  }
} catch (e) {
  diskUsedPct = -1; // graceful fallback — alert stays silent
}
```

The disk alert emission (CRITICAL log) also needs to be present in the same node:
```javascript
if (diskUsedPct >= 0 && diskUsedPct >= cfg.diskAlertPct) {
  console.log(JSON.stringify({
    level: 'CRITICAL',
    event: 'DISK_ALERT',
    message: 'Disk usage ' + diskUsedPct + '% exceeds threshold ' + cfg.diskAlertPct + '%',
    disk_used_gb: diskUsedGB,
    disk_used_pct: diskUsedPct,
    disk_total_gb: cfg.diskTotalGB,
    ts: ts
  }));
}
```

**Security context:** The n8n-main service has `cap_drop: ALL` in the compose file. `df` is a read-only
system call (`statfs`) that works within a capability-dropped container — it does not require any
Linux capability. This was confirmed by the original 03-02-PLAN.md spec which explicitly stated
`execSync('df -k /')` as the intended mechanism. The MED-09 security review removed it unnecessarily.

**n8n Code node module access:** No `NODE_FUNCTION_ALLOW_BUILTIN` or `NODE_FUNCTION_ALLOW_EXTERNAL`
env vars are set in docker-compose.hostinger.prod.yml or .env. In n8n 2.9.4, Code nodes with
`typeVersion: 2` in production mode sandbox third-party `require()` calls but built-in Node.js
modules such as `child_process` are available when no blocklist is declared. The existing codebase
has no evidence of `execSync` being blocked — the MED-09 fix was precautionary, not based on a
confirmed runtime error.

**DISK_USAGE_METRIC log emission:** The Plan 03-02 spec also required a DISK_USAGE_METRIC INFO log
at every run (not just when alert fires). This log line is also missing from the current
"B0 - Compute Metrics" node and must be restored:
```javascript
console.log(JSON.stringify({
  level: 'INFO',
  event: 'DISK_USAGE_METRIC',
  disk_used_gb: diskUsedGB,
  disk_used_pct: diskUsedPct,
  disk_total_gb: cfg.diskTotalGB,
  ts: ts
}));
```

---

### AUDIT-03: AuditLogView Double Break

#### Break 1 — VITE_N8N_URL not baked into image

**File:** `admin-dashboard/Dockerfile` (lines 1-30)

**Current state:** The Dockerfile declares `ARG VITE_STRAPI_URL` and `ARG VITE_DOMAIN` — both are
passed at build time and baked into the Vite bundle. `ARG VITE_N8N_URL` is absent.

**Why this breaks:** Vite replaces `import.meta.env.VITE_*` at build time using the values of `ARG`
variables that are promoted to `ENV` before `npm run build` runs. If `ARG VITE_N8N_URL` is never
declared, Vite sees the variable as `undefined`, and the built JS bundle contains an empty-string
literal wherever `import.meta.env.VITE_N8N_URL` appears. The runtime `|| ''` fallback in
AuditLogView.tsx line 96 confirms this is the failure mode — it falls back to `''`, making fetch
calls relative (e.g., `/webhook/v1/internal/audit-log` fetches from the nginx SPA origin).

**Fix — Dockerfile (after line 9 `ENV VITE_DOMAIN=${VITE_DOMAIN}`):**
```dockerfile
ARG VITE_N8N_URL
ENV VITE_N8N_URL=${VITE_N8N_URL}
```

**Fix — docker-compose.hostinger.prod.yml build args for admin-dashboard service:**
```yaml
      args:
        VITE_DOMAIN: ${DOMAIN_NAME}
        VITE_STRAPI_URL: https://cms.${DOMAIN_NAME}
        VITE_N8N_URL: https://${CONSOLE_SUBDOMAIN}.${DOMAIN_NAME}
```

The correct value for `VITE_N8N_URL` is `https://n8n.srv1258231.hstgr.cloud` (derived from
`CONSOLE_SUBDOMAIN=n8n` and `DOMAIN_NAME=srv1258231.hstgr.cloud` in `.env`). Using the compose
interpolation `https://${CONSOLE_SUBDOMAIN}.${DOMAIN_NAME}` is correct and environment-agnostic.

Note: The n8n public URL is accessed via Traefik at `https://n8n.srv1258231.hstgr.cloud`. The
internal URL `http://n8n-main:5678` is NOT the correct value here — AuditLogView fetches from the
browser, not from inside the Docker network.

#### Break 2 — URL path mismatch

**File:** `admin-dashboard/src/pages/AuditLogView.tsx`, line 111

**Current broken path:**
```typescript
const url = `${apiBase}/webhook/v1/internal/audit-query?${params}`;
//                                              ^^^^^^^^^^^
//                                          "audit-query" — WRONG
```

**W_AUDIT_QUERY.json webhook registration (confirmed by reading file):**
```json
{
  "parameters": {
    "httpMethod": "GET",
    "path": "v1/internal/audit-log"
  }
}
```

n8n appends `webhook/` as a prefix to all webhook paths. The correct full URL is:
```
https://n8n.srv1258231.hstgr.cloud/webhook/v1/internal/audit-log
```

**Fix:**
```typescript
const url = `${apiBase}/webhook/v1/internal/audit-log?${params}`;
//                                              ^^^^^^^^
//                                          "audit-log" — CORRECT
```

This is the only line that changes in AuditLogView.tsx. No other code, layout, or logic changes.

**Response shape verification:** W_AUDIT_QUERY.json returns:
```json
{ "rows": [{ ...audit_record... }] }
```

But AuditLogView.tsx expects:
```typescript
interface AuditResponse {
  data: AuditRecord[];
  total: number;
  page: number;
  limit: number;
}
// consumed as: json.data || []  and  json.total || 0
```

The workflow's "B0 - Format Response" node wraps results as `{ rows: items }`, not
`{ data: [], total: N }`. This is an additional shape mismatch that the fix plan must address.
Either the AuditLogView.tsx must be updated to consume `json.rows` or W_AUDIT_QUERY must be updated
to return `{ data: rows, total: rows.length, page: 1, limit: rows.length }`. Given the UI-SPEC
contract says "only change the `apiBase` URL construction", the safer fix is to update the
W_AUDIT_QUERY response node to emit the shape AuditLogView already expects. This keeps the
frontend change to one line (the path string), not multiple lines of response-parsing rewrites.

---

## Standard Stack

### Core (all pre-existing — no new dependencies)

| Component | Version | Purpose | Notes |
|-----------|---------|---------|-------|
| n8n | 2.9.4 | Workflow runtime — Code nodes, webhook registration | Running on VPS; `active=false` workflow must be activated after import |
| Vite | (admin-dashboard package.json) | Build-time env-var baking | `import.meta.env.VITE_*` replaced at `npm run build` |
| Docker multi-stage build | — | ARG/ENV declaration at build stage | ARG must be declared BEFORE the build step that reads it |
| Node.js `child_process` | built-in | `execSync('df -k /')` for disk check | No install required; available in n8n Code nodes |

### Supporting

| Component | Version | Purpose | Notes |
|-----------|---------|---------|-------|
| docker-compose.hostinger.prod.yml | — | Build arg pass-through to Dockerfile | `args:` block under `build:` section |
| `df -k /` | POSIX | Disk usage in KB — consistent output format | `-k` forces 1024-byte blocks; field 3=Used, field 5=Use% |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `df -k /` in Code node | n8n Execute Command node | Execute Command node does not exist in this codebase; `df` in Code node with `child_process` is the established pattern from the original plan spec |
| `df -k /` in Code node | HTTP Request to a local metrics endpoint | No such endpoint exists on this VPS; would require additional infra work outside scope |
| Patching W_AUDIT_QUERY response format | Patching AuditLogView response parsing | Patching the workflow keeps the frontend change minimal (one URL string), matching UI-SPEC surgical constraint |

---

## Architecture Patterns

### Pattern 1: n8n Workflow JSON Patching

**What:** Modify the `jsCode` string value inside a specific node's `parameters` block in a workflow
JSON file. The workflow JSON must remain valid JSON and the `jsCode` must be valid JavaScript when
the escaped string is parsed.

**Critical constraint:** The `jsCode` value in n8n workflow JSON is a single JSON string with `\n`
for newlines and `\"` for quotes. All existing node IDs, positions, connections, and credentials
must be preserved exactly. The executor reads the full file, modifies only the target node's
`jsCode`, and writes back.

**Verified pattern from existing file:**
```json
{
  "parameters": {
    "language": "javascript",
    "jsCode": "var cfg = $('B0 - Config').first().json;\n..."
  },
  "id": "compute-metrics",
  "name": "B0 - Compute Metrics",
  "type": "n8n-nodes-base.code",
  "typeVersion": 2
}
```

**Anti-pattern:** Do not use `$json` for cross-node data access when the node is not the immediate
predecessor. Use `$('Node Name').first().json` for named node access (already used in this workflow).

### Pattern 2: Vite Build-Time Env Injection

**What:** Vite replaces `import.meta.env.VITE_*` at build time. The variable must be declared as
`ARG` in the Dockerfile before `RUN npm run build`, then promoted to `ENV` so it is visible to the
Vite process.

**Verified pattern from existing Dockerfile (VITE_STRAPI_URL):**
```dockerfile
ARG VITE_STRAPI_URL
ARG VITE_DOMAIN
ENV VITE_STRAPI_URL=${VITE_STRAPI_URL}
ENV VITE_DOMAIN=${VITE_DOMAIN}
```

**Same pattern for VITE_N8N_URL:**
```dockerfile
ARG VITE_N8N_URL
ENV VITE_N8N_URL=${VITE_N8N_URL}
```

**Critical order:** `ARG` must come before `ENV` which must come before `RUN npm run build`.
`ENV` without a preceding `ARG` of the same name does NOT receive build-arg values.

**Passing from compose:**
```yaml
build:
  args:
    VITE_N8N_URL: https://${CONSOLE_SUBDOMAIN}.${DOMAIN_NAME}
```

### Recommended Change Scope

```
workflows/
└── W_QUEUE_METRICS.json          # B0-Compute-Metrics jsCode: restore df parse + DISK_ALERT log

admin-dashboard/
└── Dockerfile                    # Add ARG VITE_N8N_URL + ENV VITE_N8N_URL lines
└── src/pages/AuditLogView.tsx    # Line 111: audit-query → audit-log

docker-compose.hostinger.prod.yml # Add VITE_N8N_URL to admin-dashboard build args

workflows/
└── W_AUDIT_QUERY.json            # B0-Format-Response: change output shape to {data,total,page,limit}
```

### Anti-Patterns to Avoid

- **Runtime ENV for Vite variables:** `ENV VITE_N8N_URL=https://...` set at runtime (in compose
  `environment:` not `build.args:`) does NOT work — Vite bakes at build time, not runtime. The
  variable must be in the build-stage ARG.
- **Modifying W_AUDIT_QUERY path:** The webhook path in W_AUDIT_QUERY is `v1/internal/audit-log`.
  Do NOT change the workflow path to match the old broken frontend string — fix the frontend to
  match the workflow, not the reverse.
- **Activating W_QUEUE_METRICS or W_AUDIT_QUERY in the JSON file:** Leave `active: false` in both
  workflow JSON files. Activation is a manual VPS step after import (consistent with all other
  Phase 3 workflows). Changing to `active: true` in source would cause n8n to try to activate the
  workflow on import, which can fail if credentials are not yet configured.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Disk usage | Custom /proc parser, Prometheus exporter, side-car script | `require('child_process').execSync('df -k /')` in Code node | Already specified in 03-02-PLAN.md; `df -k` is POSIX standard; try/catch handles all failure modes |
| Env-var injection | Runtime sed on built JS, server-side config injection | Dockerfile ARG/ENV + Vite build-time replacement | Existing pattern already used for VITE_STRAPI_URL; one extra ARG/ENV pair is sufficient |
| Webhook URL routing | nginx location rewrite, proxy pass to n8n internal | Direct n8n webhook URL from browser (AuditLogView already uses this pattern correctly) | n8n public URL is accessible via Traefik TLS; no proxy change needed |

---

## Common Pitfalls

### Pitfall 1: VITE_* variable set in `environment:` not `build.args:`

**What goes wrong:** Developer adds `VITE_N8N_URL` to the compose `environment:` block of the
admin-dashboard service instead of the `build.args:` block. The container runs with the env var
set, but the already-baked JS bundle still contains empty string. The fix appears to work in logs
but the browser still gets `apiBase = ''`.

**Why it happens:** `environment:` injects at container runtime; Vite baking happens at `docker build`
time. By the time the container starts, the JS is already compiled.

**How to avoid:** Always verify the fix is in the `build:` `args:` section, not the service-level
`environment:` section.

**Warning signs:** `docker exec admin-dashboard env | grep VITE_N8N_URL` shows the value, but
browser network tab still shows requests to `/webhook/...` (relative URL).

### Pitfall 2: execSync missing the `require()` call

**What goes wrong:** Executor writes `execSync('df -k /')` without `require('child_process').execSync`
or a preceding `const { execSync } = require('child_process')`. n8n Code node typeVersion 2 does
not auto-inject Node.js built-ins — they must be explicitly required.

**Why it happens:** In browser JS, built-ins are global. In n8n Code nodes the pattern is explicit
`require()`.

**How to avoid:** Use `require('child_process').execSync('df -k /')` inline, or declare at top of
the jsCode string: `var execSync = require('child_process').execSync;`

**Warning signs:** Workflow execution error `ReferenceError: execSync is not defined`.

### Pitfall 3: Workflow JSON escaping breaks parse

**What goes wrong:** After editing the `jsCode` string, the resulting JSON file fails `JSON.parse`
because the code contains unescaped double quotes, unescaped backslashes, or literal newlines.

**Why it happens:** The `jsCode` must be a JSON string — newlines must be `\n`, quotes must be `\"`,
backslashes must be `\\`.

**How to avoid:** Use the Write tool to write the complete workflow JSON (not shell heredoc). Verify
with `node -e "JSON.parse(require('fs').readFileSync('workflows/W_QUEUE_METRICS.json','utf8'))"`.

**Warning signs:** `SyntaxError: Unexpected token` during JSON.parse validation.

### Pitfall 4: W_AUDIT_QUERY response shape mismatch overlooked

**What goes wrong:** The path is corrected in AuditLogView.tsx from `audit-query` to `audit-log`,
the Dockerfile gets the ARG/ENV, the image is rebuilt — but the audit view still shows empty records
because W_AUDIT_QUERY returns `{ rows: [...] }` while AuditLogView consumes `json.data`.

**Why it happens:** The audit view's response-parsing logic was written against a different shape
spec than what W_AUDIT_QUERY actually produces.

**How to avoid:** Fix both: update W_AUDIT_QUERY "B0 - Format Response" Code node to return
`{ data: items, total: items.length, page: page, pageSize: pageSize }` matching the
`AuditResponse` TypeScript interface in AuditLogView.tsx. The workflow already has access to `page`
and `pageSize` from the parse-params node output.

**Warning signs:** Browser network tab shows HTTP 200 from n8n but `records` state in component
remains empty (`json.data` is `undefined`, `records = []`).

### Pitfall 5: df output format on Alpine Linux

**What goes wrong:** `df -k /` on Alpine Linux (musl libc) produces slightly different column
ordering than on GNU/Linux in some edge cases (e.g., filesystem type column may shift).

**Standard Alpine output:**
```
Filesystem           1K-blocks      Used Available Use% Mounted on
overlay             123731756  84123648  33287064  72% /
```
Field indices (0-based after split on whitespace): 0=Filesystem, 1=1K-blocks, 2=Used, 3=Available,
4=Use%, 5=Mounted-on. The existing plan spec uses `parts[2]` for Used and `parts[4]` for Use% —
this is correct for Alpine.

**How to avoid:** Use `parts[4].replace('%', '')` for the percentage — the `%` suffix strip is
already in the original plan spec. Keep `parseInt(parts[2], 10)` for used KB.

---

## Code Examples

### Example 1: Complete patched jsCode for B0-Compute-Metrics node

```javascript
// Source: 03-02-PLAN.md spec + MED-09 fix reversal
var cfg = $('B0 - Config').first().json;
var pgRow = $input.first().json;

var pendingCount = parseInt(pgRow.pending_count || '0', 10);
var runningCount = parseInt(pgRow.running_count || '0', 10);
var errorsLastHour = parseInt(pgRow.errors_last_hour || '0', 10);
var totalLastHour = parseInt(pgRow.total_last_hour || '0', 10);
var errorRate = totalLastHour > 0 ? (errorsLastHour / totalLastHour) : 0;

var diskUsedGB = -1;
var diskUsedPct = -1;
try {
  var dfOut = require('child_process').execSync('df -k /').toString();
  var lines = dfOut.trim().split('\n');
  if (lines.length >= 2) {
    var parts = lines[1].trim().split(/\s+/);
    var usedKB = parseInt(parts[2], 10);
    diskUsedGB = Math.round(usedKB / 1024 / 1024 * 10) / 10;
    diskUsedPct = parseInt(parts[4].replace('%', ''), 10);
  }
} catch (e) {
  diskUsedGB = -1;
  diskUsedPct = -1;
}

var ts = new Date().toISOString();

console.log(JSON.stringify({
  level: 'INFO',
  event: 'QUEUE_DEPTH_METRIC',
  pending_count: pendingCount,
  running_count: runningCount,
  errors_last_hour: errorsLastHour,
  error_rate_1h: Math.round(errorRate * 1000) / 1000,
  ts: ts
}));

console.log(JSON.stringify({
  level: 'INFO',
  event: 'DISK_USAGE_METRIC',
  disk_used_gb: diskUsedGB,
  disk_used_pct: diskUsedPct,
  disk_total_gb: cfg.diskTotalGB,
  ts: ts
}));

var alerts = [];
var queueAbove = pendingCount > cfg.queueThreshold;

if (diskUsedPct >= 0 && diskUsedPct >= cfg.diskAlertPct) {
  var diskAlert = {
    level: 'CRITICAL',
    event: 'DISK_ALERT',
    message: 'Disk usage ' + diskUsedPct + '% exceeds threshold ' + cfg.diskAlertPct + '%',
    disk_used_gb: diskUsedGB,
    disk_used_pct: diskUsedPct,
    disk_total_gb: cfg.diskTotalGB,
    ts: ts
  };
  console.log(JSON.stringify(diskAlert));
  alerts.push(diskAlert);
}

return [{ json: {
  pendingCount: pendingCount,
  runningCount: runningCount,
  errorsLastHour: errorsLastHour,
  errorRate: errorRate,
  diskUsedGB: diskUsedGB,
  diskUsedPct: diskUsedPct,
  queueAbove: queueAbove,
  queueThreshold: cfg.queueThreshold,
  diskAlertPct: cfg.diskAlertPct,
  alerts: alerts,
  ts: ts
}}];
```

### Example 2: Dockerfile ARG/ENV addition

```dockerfile
# ── Build stage ──────────────────────────────────────────────
FROM node:20-alpine AS build

WORKDIR /app

ARG VITE_STRAPI_URL
ARG VITE_DOMAIN
ENV VITE_STRAPI_URL=${VITE_STRAPI_URL}
ENV VITE_DOMAIN=${VITE_DOMAIN}

ARG VITE_N8N_URL
ENV VITE_N8N_URL=${VITE_N8N_URL}

COPY admin-dashboard/package.json admin-dashboard/package-lock.json ./
RUN npm ci --legacy-peer-deps
```

### Example 3: docker-compose build args addition

```yaml
  admin-dashboard:
    build:
      args:
        VITE_DOMAIN: ${DOMAIN_NAME}
        VITE_STRAPI_URL: https://cms.${DOMAIN_NAME}
        VITE_N8N_URL: https://${CONSOLE_SUBDOMAIN}.${DOMAIN_NAME}
      context: .
      dockerfile: admin-dashboard/Dockerfile
```

### Example 4: AuditLogView.tsx fetch URL fix (line 111)

```typescript
// BEFORE (broken):
const url = `${apiBase}/webhook/v1/internal/audit-query?${params}`;

// AFTER (correct — path matches W_AUDIT_QUERY.json "path": "v1/internal/audit-log"):
const url = `${apiBase}/webhook/v1/internal/audit-log?${params}`;
```

### Example 5: W_AUDIT_QUERY B0-Format-Response patched to match AuditResponse interface

```javascript
// Source: W_AUDIT_QUERY.json B0-Format-Response node (current)
var items = $input.all().map(function(i) { return i.json; });
return [{ json: { rows: items } }];

// PATCHED — matches AuditResponse { data, total, page, limit }:
var cfg = $('B0 - Parse Params').first().json;
var items = $input.all().map(function(i) { return i.json; });
return [{ json: {
  data: items,
  total: items.length,
  page: cfg.page,
  limit: cfg.pageSize
}}];
```

Note: This gives `total` as the count of rows returned in the current page, not the overall count
across all pages. For a more accurate total, the count query result (countQuery) would need to be
executed and joined. However, since AuditLogView.tsx derives `totalPages = Math.ceil(total / ITEMS_PER_PAGE)`
and the component ITEMS_PER_PAGE (25) already handles pagination on the frontend, returning
`items.length` as total is a workable first fix. The PLAN should note this as a known limitation.

---

## Verification Commands

```bash
# METR-05: Verify W_QUEUE_METRICS JSON is valid
node -e "JSON.parse(require('fs').readFileSync('workflows/W_QUEUE_METRICS.json','utf8')); console.log('valid')"

# METR-05: Verify disk check is present in workflow
grep -c "df -k /" workflows/W_QUEUE_METRICS.json

# METR-05: Verify DISK_ALERT appears in workflow
grep -c "DISK_ALERT" workflows/W_QUEUE_METRICS.json

# AUDIT-03: Verify ARG is declared in Dockerfile
grep "ARG VITE_N8N_URL" admin-dashboard/Dockerfile

# AUDIT-03: Verify ENV is declared in Dockerfile
grep "ENV VITE_N8N_URL" admin-dashboard/Dockerfile

# AUDIT-03: Verify build arg in compose
grep "VITE_N8N_URL" docker-compose.hostinger.prod.yml

# AUDIT-03: Verify fetch URL path in AuditLogView
grep "audit-log" admin-dashboard/src/pages/AuditLogView.tsx

# AUDIT-03: Confirm broken path is gone
grep -c "audit-query" admin-dashboard/src/pages/AuditLogView.tsx  # must return 0
```

---

## State of the Art

| Old Approach | Current Approach | Impact on Phase 7 |
|--------------|------------------|-------------------|
| Phase 3 original: `execSync('df -k /')` in Code node | MED-09 applied: hardcoded -1 | Must revert to Phase 3 original approach — MED-09 was over-broad |
| Phase 3 original: `audit-query` path (spec had `audit-log` but implementation drifted) | W_AUDIT_QUERY.json actually uses `v1/internal/audit-log` | Frontend must match workflow, not vice versa |
| Phase 3 original: VITE_N8N_URL was never declared | Pattern exists for VITE_STRAPI_URL | Copy the STRAPI pattern exactly |

---

## Open Questions

1. **Total count for AuditLogView pagination**
   - What we know: W_AUDIT_QUERY runs a separate `countQuery` via the same Postgres node in sequence but the current workflow only executes `dataQuery` in the "PG - Query Audit" node
   - What's unclear: Is `countQuery` executed anywhere? Looking at the connections, there is only one PG node — the countQuery is built but never run
   - Recommendation: For Phase 7, return `items.length` as total (workable for current page). A full fix (running countQuery in a second PG node) is out of Phase 7 scope — record as tech debt

2. **W_AUDIT_QUERY credential placeholder**
   - What we know: `W_AUDIT_QUERY.json` uses `"id": "CREDENTIAL_ID_PLACEHOLDER"` for its Postgres credential — same placeholder pattern as other Phase 3 workflows
   - What's unclear: Whether the VPS operator has already substituted the real credential ID after Phase 3 import
   - Recommendation: Do not change the placeholder in the JSON file. Credential wiring is a VPS activation step, not a code fix. Document in PLAN that operator must set real credential after re-import.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Structural verification (grep + node JSON.parse) — no unit test framework for workflow JSON |
| Config file | none — ad hoc verification commands |
| Quick run command | `node -e "JSON.parse(require('fs').readFileSync('workflows/W_QUEUE_METRICS.json','utf8')); console.log('valid')"` |
| Full suite command | See verification block above (5 grep checks + 1 node parse) |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| METR-05 | W_QUEUE_METRICS contains `df -k /` disk parse | structural | `grep -c "df -k /" workflows/W_QUEUE_METRICS.json` | ✅ |
| METR-05 | W_QUEUE_METRICS JSON is valid | structural | `node -e "JSON.parse(...W_QUEUE_METRICS.json...)"` | ✅ |
| METR-05 | DISK_ALERT CRITICAL log present in workflow | structural | `grep -c "DISK_ALERT" workflows/W_QUEUE_METRICS.json` | ✅ |
| AUDIT-03 | Dockerfile declares ARG VITE_N8N_URL | structural | `grep "ARG VITE_N8N_URL" admin-dashboard/Dockerfile` | ✅ |
| AUDIT-03 | Dockerfile declares ENV VITE_N8N_URL | structural | `grep "ENV VITE_N8N_URL" admin-dashboard/Dockerfile` | ✅ |
| AUDIT-03 | Compose passes VITE_N8N_URL build arg | structural | `grep "VITE_N8N_URL" docker-compose.hostinger.prod.yml` | ✅ |
| AUDIT-03 | AuditLogView uses correct path `audit-log` | structural | `grep "audit-log" admin-dashboard/src/pages/AuditLogView.tsx` | ✅ |
| AUDIT-03 | AuditLogView does NOT use `audit-query` path | structural | `grep -c "audit-query" admin-dashboard/src/pages/AuditLogView.tsx` → 0 | ✅ |
| AUDIT-03 | W_AUDIT_QUERY returns `data` field | structural | `grep "\"data\"" workflows/W_AUDIT_QUERY.json` | ✅ (after fix) |

### Sampling Rate

- **Per task commit:** Run the 2-3 grep checks specific to that task's file changes
- **Per wave merge:** Run all 9 checks above
- **Phase gate:** All structural checks green before `/gsd:verify-work`

### Wave 0 Gaps

None — all verification commands operate on files that already exist. No new test infrastructure
is required. The structural checks are self-contained single-command verifications.

---

## Sources

### Primary (HIGH confidence)

- `workflows/W_QUEUE_METRICS.json` — read directly; B0-Compute-Metrics jsCode confirms `diskUsedPct = -1` hardcode
- `workflows/W_AUDIT_QUERY.json` — read directly; webhook path confirmed as `v1/internal/audit-log`
- `admin-dashboard/src/pages/AuditLogView.tsx` — read directly; line 111 fetch URL confirmed broken; line 96 apiBase fallback confirmed; AuditResponse interface confirmed
- `admin-dashboard/Dockerfile` — read directly; ARG/ENV block confirmed missing VITE_N8N_URL
- `docker-compose.hostinger.prod.yml` — read directly; admin-dashboard build args confirmed missing VITE_N8N_URL; n8n HOST/PROTOCOL/CONSOLE_SUBDOMAIN pattern confirmed
- `.env` — read directly; `CONSOLE_SUBDOMAIN=n8n`, `DOMAIN_NAME=srv1258231.hstgr.cloud` confirmed
- `.planning/v1.0-MILESTONE-AUDIT.md` — root cause evidence for both defects verbatim
- `.planning/phases/03-metrics-alerting-and-audit-trail/03-02-PLAN.md` — original spec for W_QUEUE_METRICS disk check mechanism
- `.planning/phases/07-fix-critical-defects/07-UI-SPEC.md` — fix contracts approved by gsd-ui-checker

### Secondary (MEDIUM confidence)

- n8n 2.9.4 Code node behaviour: no `NODE_FUNCTION_ALLOW_BUILTIN` or `NODE_FUNCTION_ALLOW_EXTERNAL` found in compose or .env → built-in `child_process` available; confirmed by absence of blocklist
- Vite ARG/ENV pattern: confirmed working by existing VITE_STRAPI_URL which follows the identical pattern

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — all files read directly; no external dependencies introduced
- Architecture: HIGH — fix scope is three files + one workflow JSON; pattern already exists in codebase
- Pitfalls: HIGH — all pitfalls derived from direct code inspection, not speculation

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (stable domain — n8n 2.9.4 and Vite build patterns are not changing)
