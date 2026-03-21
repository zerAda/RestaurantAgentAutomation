# Phase 1, Plan 01 — Remove Duplicate Agent-Chat Extension

**Phase:** 01-stability
**Plan:** 01
**Requirements:** STBL-01, STBL-03
**Wave:** 1
**Autonomous:** true

---

## Objective

Remove the `src/extensions/agent-chat/` directory and the `register()` body in `src/index.ts` so that `POST /api/agent/chat` is registered exactly once — via the `src/api/system-config/routes/agent-chat.ts` file.

Currently three registrations exist for the same path:
1. `src/api/system-config/routes/agent-chat.ts` (Redis-RAG controller — canonical, keep)
2. `src/extensions/agent-chat/routes/agent-chat.ts` (simpler controller — remove)
3. `src/index.ts register()` — programmatic registration of extension routes (remove body, keep hook)

Additionally, the extensions version has a `GET /api/agent/tools` route that is not present in the system-config version. This handler must be migrated to the system-config API before the extension directory is deleted.

**Why the system-config version is canonical:**
- Uses Redis rate limiting (20 req/min per user)
- Performs 16-slice Redis-cached RAG context
- Logs to `llm-usage-log` and `agent-session`
- Is co-located with its content type

**Rollback:** If anything breaks at runtime, the extension files can be restored from git (`git checkout src/extensions/agent-chat/`). The `register()` body can be restored by reverting `src/index.ts`. No database changes are made.

---

## Task 1 — Migrate `tools` handler and add its route to system-config

**Files:**
- `project/inventory-cms/src/api/system-config/controllers/agent-chat.ts`
- `project/inventory-cms/src/api/system-config/routes/agent-chat.ts`

**Action:**

The `src/extensions/agent-chat/controllers/agent-chat.ts` file contains a `tools` handler (GET /api/agent/tools) that returns the MCP tool catalogue. This handler does not exist in the system-config controller. It must be added before the extension is deleted.

Step 1 — Add the `tools` export to `src/api/system-config/controllers/agent-chat.ts`.

Read the existing file at `project/inventory-cms/src/api/system-config/controllers/agent-chat.ts`. The file exports a default object containing at minimum a `chat` method. Append a `tools` method to that same default export. The `tools` method body must be copied verbatim from `src/extensions/agent-chat/controllers/agent-chat.ts` lines 196-270 (the `tools` function). That function builds a `tools` array of 10 tool definitions (get_orders, get_products, get_customers, get_ingredients, get_ai_learnings, get_funnel_events, get_workflow_errors, update_order_status, get_llm_usage, get_marketing_campaigns) and returns `ctx.body = { data: { tools, version, baseUrl, auth, note } }`.

Step 2 — Add the `GET /api/agent/tools` route to `src/api/system-config/routes/agent-chat.ts`.

The current file exports a routes array with only one entry (POST /agent/chat with `auth: false`). Add a second route entry:
```json
{
  "method": "GET",
  "path": "/agent/tools",
  "handler": "agent-chat.tools",
  "config": {
    "auth": false,
    "policies": [],
    "middlewares": []
  }
}
```

Note: The extension version used scope-based auth for /agent/tools. Since this is a non-sensitive tool catalogue (no business data, just endpoint descriptions), `auth: false` is acceptable and consistent with the existing agent-chat route file's pattern. If the team later wants auth here, it can be added without touching the controller.

**Acceptance criteria:**
- `src/api/system-config/controllers/agent-chat.ts` exports both `chat` and `tools` methods
- `src/api/system-config/routes/agent-chat.ts` exports both the POST /agent/chat and GET /agent/tools routes
- TypeScript compiler (`cd project/inventory-cms && npx tsc --noEmit`) reports zero errors on these two files

**Verify:**
```bash
cd "project/inventory-cms" && npx tsc --noEmit 2>&1 | grep -E "agent-chat|error" | head -20
```

---

## Task 2 — Remove `src/extensions/agent-chat/` and clean `src/index.ts register()`

**Files:**
- `project/inventory-cms/src/extensions/agent-chat/` (delete entire directory)
- `project/inventory-cms/src/index.ts`

**Action:**

Step 1 — Delete the extensions/agent-chat directory.

Delete these files (do not leave empty directories):
- `project/inventory-cms/src/extensions/agent-chat/controllers/agent-chat.ts`
- `project/inventory-cms/src/extensions/agent-chat/routes/agent-chat.ts`
- The `controllers/` and `routes/` subdirectories under `src/extensions/agent-chat/`
- The `src/extensions/agent-chat/` directory itself

Step 2 — Remove the agent-chat registration body from `src/index.ts`.

Read the full current content of `project/inventory-cms/src/index.ts`. The `register()` function body (lines 9-55) calls `strapi.controller()` and `strapi.server.routes()` for agent-chat. This entire try/catch block must be removed. The `register()` hook itself must remain as an exported no-op (Strapi requires the export shape).

Replace the `register()` body with:
```typescript
register({ strapi }: { strapi: Core.Strapi }) {
  // Agent-chat routes are now registered via src/api/system-config/routes/agent-chat.ts
  // No programmatic route registration needed.
},
```

The `bootstrap()` function and all imports (`import type { Core }`, `import { seedRestaurantMenu }`) must be preserved exactly as-is.

Step 3 — Verify no other file in the project imports from `src/extensions/agent-chat/`.

Run:
```bash
grep -r "extensions/agent-chat" project/inventory-cms/src/ --include="*.ts" -l
```

If any file other than the deleted ones appears in the output, update that file's import to point to the system-config controller or remove the import.

**Acceptance criteria:**
- `project/inventory-cms/src/extensions/agent-chat/` directory does not exist
- `project/inventory-cms/src/index.ts` `register()` contains no `strapi.server.routes()` call
- No file in `project/inventory-cms/src/` imports from `./extensions/agent-chat`
- `grep -r "api::agent-chat" project/inventory-cms/src/` returns zero matches

**Verify:**
```bash
ls "project/inventory-cms/src/extensions/agent-chat" 2>&1 | grep -c "No such file" && grep -c "agent-chat.agent-chat" project/inventory-cms/src/index.ts || echo "FAIL: agent-chat refs remain"
```

---

## Task 3 — TypeScript compile check and smoke test

**Files:** No files modified — verification only.

**Action:**

Step 1 — Run the TypeScript compiler in no-emit mode from the CMS directory:
```bash
cd project/inventory-cms && npx tsc --noEmit
```
Zero errors is required. If errors appear, fix them before proceeding to Task 4 (Plan 02).

Step 2 — If Strapi is running locally or on VPS, perform a restart smoke test. If not running locally, this step is deferred to the CI build.

On VPS (SSH to 72.60.190.192 as `deploy`):
```bash
cd /opt/resto/current && docker compose restart cms && sleep 15
curl -s http://127.0.0.1:1337/_health
```
Expect HTTP 204.

Step 3 — Verify the route count for /api/agent/chat by checking Strapi startup logs:
```bash
docker logs current-cms-1 2>&1 | grep -i "agent" | tail -20
```
Expect to see the route loaded once (from system-config API directory), not three times.

**Acceptance criteria:**
- `npx tsc --noEmit` exits with code 0
- `GET /_health` returns 204 after restart
- Strapi logs show no "agent-chat extension registration warning" message

**Verify:**
```bash
cd project/inventory-cms && npx tsc --noEmit && echo "TS OK"
```

---

## Rollback Strategy

If this plan causes a Strapi startup failure:

```bash
# On VPS — restore from git
cd /opt/resto/current
git checkout project/inventory-cms/src/index.ts
git checkout project/inventory-cms/src/extensions/agent-chat/
docker compose restart cms
```

If the CI build fails, the existing Docker image (previous SHA) remains deployed. No database changes are made in this plan, so rollback requires only a git revert and image rebuild.

---

## Success Criteria

- `POST /api/agent/chat` is registered exactly once in Strapi at startup
- The Redis-RAG system-config implementation handles all agent chat calls
- The MCP tools catalogue `GET /api/agent/tools` is available via the system-config route
- Zero TypeScript compilation errors
- CMS health endpoint returns 204 after restart
- CI build passes (docker build succeeds, image pushed to GHCR)
