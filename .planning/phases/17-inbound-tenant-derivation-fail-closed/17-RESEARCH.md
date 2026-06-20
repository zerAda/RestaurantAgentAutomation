# Phase 17: Inbound Tenant Derivation (Fail-Closed) — Research

**Researched:** 2026-06-20
**Domain:** n8n 2.9.4 workflow JSON surgery — inbound adapter auth nodes + Postgres resolver rung + fail-closed security events
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TEN-03 | Inbound adapters resolve tenant from `channel_identities`: `B0 - Apply Auth Context` in `W1_IN_WA.json`, `W2_IN_IG.json`, `W3_IN_MSG.json` uses the already-parsed `phone_number_id`/`recipient_id` instead of falling through to `DEFAULT_TENANT_ID`. An unknown identity fails closed (parked/rejected with a log event) — it does NOT default to `'default'`. | Sections 1–6 below document the exact node JS, the resolver SQL, the fail-closed path, and the 3 INVENTORY-17 fallback sites to remove. |
</phase_requirements>

---

## Summary

Phase 17 is pure surgical workflow JSON editing. The `channel_identities` routing table from Phase 16 exists and is seeded. The inbound adapters already parse the channel-native identity signal (`phone_number_id` for WhatsApp in `B0 - Parse & Canonicalize`; `recipient_id` for Instagram and Messenger in their respective parse nodes) and store it on `inbound_envelope.meta`. The `B0 - Apply Auth Context` Code node in all three adapters then discards that signal for Meta webhook paths, writing hardcoded UUID fallbacks or env defaults instead. This phase inserts one new Postgres lookup rung between `B0 - Resolve Client (DB)` and `B0 - Apply Auth Context` that queries `channel_identities` by `(channel, identity)` WHERE `is_active = true`. If a row is found, `tenant_id` and `restaurant_id` are taken from that row. If no row is found, the workflow writes a `UNKNOWN_CHANNEL_IDENTITY` / `TENANT_RESOLUTION_FAILED` security event and stops — never forwarding to core.

The three INVENTORY-17 sites (from `docs/adr/0002-tenant-id-fallback-inventory.md`) are:
- `workflows/W0_MODULE_GUARD.json` node `"Module Guard"` — `|| $env.DEFAULT_TENANT_ID || 'default'` (the guard's own tenant fallback becomes moot once callers always supply a real UUID)
- `workflows/W1_IN_WA.json` node `"B0 - Apply Auth Context"` — `defaultTenantId = envDefaultTenantId || fallbackTenantId` used for `meta_signature` and `legacy_shared` modes
- `workflows/W_DRIVER_ONBOARDING.json` node `"Ensure Customer Profile"` — `$json.tenant_id || $env.DEFAULT_TENANT_ID || '00000000-0000-0000-0000-000000000001'`

W2_IN_IG and W3_IN_MSG have hardcoded UUID fallbacks in `B0 - Apply Auth Context` (not annotated with `INVENTORY-17` but are the same structural problem) that also must be replaced.

**Primary recommendation:** Add a `n8n-nodes-base.postgres` node named `"B0 - Resolve Channel Identity (DB)"` between `B0 - Resolve Client (DB)` and `B0 - Apply Auth Context` in each of W1/W2/W3, using credential `"postgres-main"`, querying `channel_identities` by the parsed identity. Replace the hardcoded fallback branches in `B0 - Apply Auth Context` with the result. Route no-match to a new `"B0 - Log Tenant Unresolved (DB)"` security-events INSERT + `"END - Drop/Done"` (never to core).

---

## 1. Exact Shape of `B0 - Apply Auth Context` in Each Adapter

### W1_IN_WA.json — node `"B0 - Apply Auth Context"` (id: `80046a7e-854b-4e57-b467-6f04fdc9f0ad`)

**Position in flow:** `B0 - Resolve Client (DB)` → `B0 - Apply Auth Context` → `B0 - Seal Tenant Context`

**How identity is parsed:** In `B0 - Parse & Canonicalize` (id: `57c1bc81-2ffe-4ec4-bb34-c90c01c8da25`), `phone_number_id` is extracted from `value.metadata.phone_number_id` (WhatsApp native payload) and stored at `inbound_envelope.meta.phone_number_id`. The node output also sets `channel: 'whatsapp'`.

**The fallback branch (INVENTORY-17 annotation present):**
```javascript
// In B0 - Apply Auth Context jsCode:
const envDefaultTenantId = ($env.DEFAULT_TENANT_ID || '').toString().trim();
const envDefaultRestaurantId = ($env.DEFAULT_RESTAURANT_ID || '').toString().trim();
const legacyDefaultIds = (($env.LEGACY_DEFAULT_IDS || 'false')...);
const fallbackTenantId = legacyDefaultIds ? '00000000-0000-0000-0000-000000000001' : '';
const defaultTenantId = envDefaultTenantId || fallbackTenantId;
// ...
} else if (metaAuthEnabled && metaSigValid) {
  tenantId = defaultTenantId;           // <-- THE GAP: uses env/fallback, not channel_identities
  restaurantId = defaultRestaurantId;
  authMode = 'meta_signature';
} else if (legacyOk && legacyAllowed) {
  tenantId = defaultTenantId;           // <-- same gap
  restaurantId = defaultRestaurantId;
  authMode = 'legacy_shared';
}
```

The `__inventory_15` key on the node reads: `"INVENTORY-15: defaultTenantId is used for meta_signature and legacy_shared auth modes. This is the Phase-17 resolution gap — real tenant must come from channel_identities lookup."`

**Where tenantId is stamped:** `return [{ json: { ...e, tenantId, restaurantId, conversationKey, tenant_context, _auth: {...} } }]`

### W2_IN_IG.json — node `"B0 - Apply Auth Context"` (id: `1d94ff21-11e5-4aff-b5f9-946d84ab576b`)

**Position in flow:** `B0 - Contract Valid?` → `B0 - Resolve Client (DB)` → `B0 - Apply Auth Context` → `B0 - Seal Tenant Context`

**How identity is parsed:** In `B0 - Parse & Canonicalize` (id: `c6dd375c-ebed-4897-a874-cd4ca958e753`), `recipient_id` is extracted from `messaging.recipient?.id` and stored at `inbound_envelope.meta.recipient_id`. The node output sets `channel: 'instagram'`.

**The hardcoded fallback (NO `__inventory_15` annotation — must also be fixed):**
```javascript
} else if (metaAuthEnabled && metaSigValid) {
  tenantId = '00000000-0000-0000-0000-000000000001';  // <-- hardcoded, not from channel_identities
  restaurantId = '00000000-0000-0000-0000-000000000000';
  authMode = 'meta_signature';
} else if (legacyOk && legacyAllowed) {
  tenantId = '00000000-0000-0000-0000-000000000001';  // <-- hardcoded
  restaurantId = '00000000-0000-0000-0000-000000000000';
  authMode = 'legacy_shared';
}
```

Note: W2_IN_IG also has a duplicate `const metaSigValid` declaration in `B0 - Apply Auth Context` (redeclared after use) — this is a latent JS bug; Phase 17 rewrite fixes it.

### W3_IN_MSG.json — node `"B0 - Apply Auth Context"` (id: `0aba4d61-8e1b-4f65-b17b-a02515c8685f`)

**Position in flow:** Identical structure to W2_IN_IG.

**How identity is parsed:** Same `B0 - Parse & Canonicalize` logic, `recipient_id` from `messaging.recipient?.id`, stored at `inbound_envelope.meta.recipient_id`. Channel set to `'messenger'`.

**The hardcoded fallback:**
```javascript
} else if (metaAuthEnabled && metaSigValid) {
  tenantId = '00000000-0000-0000-0000-000000000001';  // <-- hardcoded
  restaurantId = '00000000-0000-0000-0000-000000000000';
  authMode = 'meta_signature';
} else if (legacyOk && legacyAllowed) {
  tenantId = '00000000-0000-0000-0000-000000000001';  // <-- hardcoded
  restaurantId = '00000000-0000-0000-0000-000000000000';
  authMode = 'legacy_shared';
}
```

---

## 2. The Concrete Fix — Resolver Rung

### Mechanism Decision: Postgres Node Using `postgres-main` Credential

**Rationale:** The existing pattern for DB lookups in all three adapters is `n8n-nodes-base.postgres` `typeVersion: 2`, `operation: "executeQuery"`, credential `{ "postgres": { "id": "postgres-main", "name": "postgres-main" } }`. This is proven in `W1_IN_WA.json` node `"B0 - Resolve Client (DB)"` (id: `6954cbb3-8346-4255-b5c7-5aa8aa9e81e5`) and node `"B1a - Log Admin Access Attempt"` (explicit credential block). The `channel_identities` table lives in the n8n DB — the same DB the Postgres credential targets. No HTTP call, no new credential, no cross-DB hop required.

**Credential to use:**
```json
"credentials": {
  "postgres": {
    "id": "postgres-main",
    "name": "postgres-main"
  }
}
```

### Insertion Point

Insert the new Postgres node between `B0 - Resolve Client (DB)` and `B0 - Apply Auth Context` in W1/W2/W3. The `connections` block must be updated:
- `B0 - Resolve Client (DB)` → `B0 - Resolve Channel Identity (DB)` (new)
- `B0 - Resolve Channel Identity (DB)` → `B0 - Apply Auth Context` (existing)

### The SQL

```sql
SELECT tenant_id::text, restaurant_id::text
FROM channel_identities
WHERE channel = $1
  AND identity = $2
  AND is_active = true
LIMIT 1;
```

**Parameters (`additionalFields.queryParams` expression):**

For W1_IN_WA (WhatsApp — `phone_number_id`):
```
={{[$json.channel, $json.inbound_envelope?.meta?.phone_number_id || '']}}
```

For W2_IN_IG (Instagram — `recipient_id`):
```
={{[$json.channel, $json.inbound_envelope?.meta?.recipient_id || '']}}
```

For W3_IN_MSG (Messenger — `recipient_id`):
```
={{[$json.channel, $json.inbound_envelope?.meta?.recipient_id || '']}}
```

The query returns `tenant_id` and `restaurant_id` as text columns (UUID cast to text). If no row matches, the node returns `null` columns (the LIMIT 1 returns zero rows → the node output has those fields as `null`/`undefined`).

### Updated `B0 - Apply Auth Context` Logic

After the resolver rung, `B0 - Apply Auth Context` reads `$json.ci_tenant_id` and `$json.ci_restaurant_id` (set by the resolver Code shim, see below) instead of the env default. The auth ladder becomes:

```javascript
// NEW: channel_identities result (highest priority for Meta channels)
const ciTenantId   = ($json.ci_tenant_id || '').toString().trim();
const ciRestaurantId = ($json.ci_restaurant_id || '').toString().trim();
const ciResolved   = !!(ciTenantId && ciRestaurantId);

if (matched && e.tenant_id && e.restaurant_id) {
  // api_client token: unchanged
  tenantId = e.tenant_id.toString();
  restaurantId = e.restaurant_id.toString();
  authMode = 'api_client';
} else if (ciResolved && (metaAuthEnabled && metaSigValid)) {
  // Meta sig + channel_identities resolution: REAL tenant
  tenantId = ciTenantId;
  restaurantId = ciRestaurantId;
  authMode = 'meta_signature';
  scopes = ['inbound:write'];
} else if (ciResolved && legacyOk && legacyAllowed) {
  // Legacy shared token + channel_identities: REAL tenant
  tenantId = ciTenantId;
  restaurantId = ciRestaurantId;
  authMode = 'legacy_shared';
  scopes = ['legacy_shared'];
} else {
  // NO resolution → authMode stays 'deny'
  // denyReason = 'UNKNOWN_CHANNEL_IDENTITY' set below
  authMode = 'deny';
}
// REMOVE: defaultTenantId, fallbackTenantId, envDefaultTenantId constructs
// REMOVE: || 'default', || '00000000-...-000001' hardcoded branches
```

**Note for W1_IN_WA:** The Postgres resolver node outputs columns directly on `$json` (e.g. `$json.tenant_id`, `$json.restaurant_id`). Since `B0 - Resolve Client (DB)` already uses those column names for the api_client path, a Code shim node between the resolver and `B0 - Apply Auth Context` should namespace the channel_identities result to avoid collision:

```javascript
// "B0 - Map Channel Identity Result" (Code node, new)
const row = $json;
return [{json: {
  ...row,
  ci_tenant_id:    row.tenant_id    || null,  // from channel_identities SELECT
  ci_restaurant_id: row.restaurant_id || null,
}}];
```

This avoids the api_client `tenant_id` column (from `B0 - Resolve Client (DB)`) being clobbered by the channel_identities result when both nodes output to the same item. Alternatively, keep both nodes separate items and use `$('B0 - Resolve Client (DB)').first().json` vs `$('B0 - Resolve Channel Identity (DB)').first().json` — but the shim pattern is simpler and matches existing adapter conventions.

---

## 3. Fail-Closed Semantics

### What the Existing Auth-Failure Pattern Looks Like

The existing pattern for auth failure is already well-established in all three adapters:
- `B0 - Apply Auth Context` sets `authMode = 'deny'` and `denyReason`
- `B0 - Token OK?` (IF node) checks `$json._auth.authOk === true` AND `$json._auth.scopeOk === true`
- On `false` branch: routes to `B0 - Log Deny (DB)` (a Postgres `security_events` INSERT) → `END - Drop/Done`
- W1_IN_WA has a pre-ACK path so the HTTP 200 is sent before processing; the deny is purely internal (no HTTP response to Meta — Meta never sees a denial, just a 200 ACK, which is correct for Meta webhook semantics)

### Fail-Closed Action for Unknown Identity

When `ciResolved = false` AND `matched = false` (no api_client token), `authMode` stays `'deny'` and `denyReason` must be set to `'UNKNOWN_CHANNEL_IDENTITY'`. The existing `B0 - Token OK?` IF branch then routes to `B0 - Log Deny (DB)` which inserts into `security_events`.

**The existing `B0 - Log Deny (DB)` INSERT in W1_IN_WA:**
```sql
INSERT INTO security_events(
  tenant_id, restaurant_id, conversation_key, channel, user_id,
  event_type, severity, payload_json
) VALUES (
  $1,$2,$3,$4,$5,$6,'HIGH',
  jsonb_build_object('token_hash',$7,'ip',$8,'ua',$9,'tenant_hint',$10,
                     'restaurant_hint',$11,'auth_mode',$12,'required_scopes',$13::jsonb,
                     'scopes',$14::jsonb,'endpoint_group',$15,'endpoint_path',$16)
) RETURNING 1;
```
Parameters: `[null, null, null, $json.channel, $json.userId, ($json._auth.denyReason || 'AUTH_DENY'), ...]`

For the `UNKNOWN_CHANNEL_IDENTITY` case, `denyReason = 'UNKNOWN_CHANNEL_IDENTITY'` maps directly to `event_type` at `$6`. No new node is required — the existing deny path already writes to `security_events`. The planner may optionally add an additional security event log node named `"B0 - Log Tenant Unresolved (DB)"` that captures the channel/identity pair in `payload_json` for forensics, but the minimum viable path is `denyReason = 'UNKNOWN_CHANNEL_IDENTITY'` flowing through the existing `B0 - Token OK?` → `B0 - Log Deny (DB)` chain.

**Key constraint from SRE skill:** The message must NOT enter the core agent (`B1 - Execute CORE_AGENT`) with an unresolved tenant. The fail-closed path must route to `END - Drop/Done` via the existing deny branch without touching `B0 - Module Guard` or `B0 - Idempotency (DB)` with a null `conversationKey`.

### Parking vs Rejection

Meta webhook semantics require a 200 ACK regardless of internal disposition (W1_IN_WA already sends `RESP - 200 ACK` before `B0 - Apply Auth Context` fires). IG and MSG adapters send `RESP - 200 OK` at `END - Drop/Done`. In all cases "parked/rejected" means: security event written, message dropped, no core processing — the external caller always receives 200. This is the correct behavior for Meta platforms.

---

## 4. The 3 INVENTORY-17 Sites and What to Remove

### Site 1: `workflows/W0_MODULE_GUARD.json`, node `"Module Guard"`

**Current fallback line:**
```javascript
const tenantId = $input.first().json.tenant_id || $env.DEFAULT_TENANT_ID || 'default';
```
(node `"Module Guard"`, `__inventory_15` key present confirming INVENTORY-17 scope)

**Fix:** Remove the `|| $env.DEFAULT_TENANT_ID || 'default'` tail entirely. After Phase 17, callers always supply a real UUID from `channel_identities`. Replace with a fail-closed guard:
```javascript
const tenantId = ($input.first().json.tenant_id || '').toString().trim();
if (!tenantId) {
  return [{ json: { allowed: false, reason: 'GUARD_ERROR: tenant_id not provided (UNKNOWN_CHANNEL_IDENTITY)' } }];
}
```
This ensures the guard itself also fails closed if called without a real tenant (defense-in-depth).

**Remove the `__inventory_15` annotation key** from the node JSON once this fix is applied.

### Site 2: `workflows/W1_IN_WA.json`, node `"B0 - Apply Auth Context"` (id: `80046a7e-...`)

**Current fallback construct:**
```javascript
const envDefaultTenantId = ($env.DEFAULT_TENANT_ID || '').toString().trim();
const envDefaultRestaurantId = ($env.DEFAULT_RESTAURANT_ID || '').toString().trim();
const prodEnforceDefaults = ...;
const legacyDefaultIds = ...;
const fallbackTenantId = legacyDefaultIds ? '00000000-0000-0000-0000-000000000001' : '';
const fallbackRestaurantId = legacyDefaultIds ? '00000000-0000-0000-0000-000000000000' : '';
const defaultTenantId = envDefaultTenantId || fallbackTenantId;
const defaultRestaurantId = envDefaultRestaurantId || fallbackRestaurantId;
```

**Remove:** All the above `defaultTenantId` / `defaultRestaurantId` / `fallbackTenantId` constructs. Replace both `tenantId = defaultTenantId` assignments (in `meta_signature` and `legacy_shared` branches) with `tenantId = ciTenantId` (from resolver rung).

**Remove the `__inventory_15` annotation key** from the node JSON once this fix is applied.

### Site 3: `workflows/W_DRIVER_ONBOARDING.json`, node `"Ensure Customer Profile"` (id: `e6a4b12c-...`)

**Current fallback in `queryParams`:**
```javascript
[$json.phone,
 $json.tenant_id || $env.DEFAULT_TENANT_ID || '00000000-0000-0000-0000-000000000001',
 $json.restaurant_id || $env.DEFAULT_RESTAURANT_ID || '00000000-0000-0000-0000-000000000000']
```

**Context:** W_DRIVER_ONBOARDING is triggered by a Strapi webhook (`POST /strapi/driver-created`). It does not go through the Meta channel identity path. The driver payload comes from Strapi which owns the data plane. The fix here is different: the Strapi webhook payload should carry `tenant_id` and `restaurant_id` in the driver entry (from the Strapi content type), making the fallback unnecessary. Remove the `|| $env.DEFAULT_TENANT_ID || '...'` fallback; if `$json.tenant_id` is absent, fail the INSERT explicitly (it will throw a NOT NULL constraint violation, which is the correct behavior — a driver without a tenant is a data error).

**Simpler acceptable fix:** Remove only the `|| '00000000-0000-0000-0000-000000000001'` UUID literal fallback, leaving `$json.tenant_id || $env.DEFAULT_TENANT_ID` (the env var fallback is acceptable if documented as single-tenant-mode only). However the Phase 17 success criteria say "no bare `|| 'default'` remains" and the ADR says "superseded by trusted derivation." The cleanest fix for Phase 17 is:
```javascript
[$json.phone,
 $json.tenant_id,      // null if absent → INSERT fails closed (correct)
 $json.restaurant_id]  // null if absent → INSERT fails closed (correct)
```
This makes the data error loud instead of silently using a wrong tenant.

**Remove the `__inventory_15` annotation key** from the node JSON once this fix is applied.

### Update `docs/adr/0002-tenant-id-fallback-inventory.md`

After fixing all three sites, update the ADR table status column for occurrences #2, #3, #4 from `ANNOTATED` to `REMOVED (Phase 17)` and update the post-Phase-17 state section. A post-Phase-17 repo grep for `|| 'default'` and `DEFAULT_TENANT_ID` on tenant paths should return zero workflow matches (only the UI occurrence #5 in `useEntitlements.ts` remains, Phase 21 scope).

---

## 5. How to Test Without Live n8n/VPS

### Structural CI Assertions (static JSON checks)

These are shell/jq checks on the workflow JSON files, following the Phase 15/16 assertion pattern. Add to a new `phase-17-assertions.yml` GitHub Actions workflow:

**Check 1: Resolver node exists in W1/W2/W3**
```bash
jq -e '.nodes[] | select(.name == "B0 - Resolve Channel Identity (DB)")' workflows/W1_IN_WA.json
jq -e '.nodes[] | select(.name == "B0 - Resolve Channel Identity (DB)")' workflows/W2_IN_IG.json
jq -e '.nodes[] | select(.name == "B0 - Resolve Channel Identity (DB)")' workflows/W3_IN_MSG.json
```

**Check 2: No `|| 'default'` remains on the tenant path in workflow JSONs**
```bash
# Must return zero matches in workflow files (INVENTORY-17 sites removed)
count=$(grep -c "'default'" workflows/W0_MODULE_GUARD.json workflows/W1_IN_WA.json \
  workflows/W_DRIVER_ONBOARDING.json 2>/dev/null || true)
if [ "$count" -gt 0 ]; then echo "FAIL: default fallback remains"; exit 1; fi
```

**Check 3: No `INVENTORY-17` annotation markers remain** (they should be removed once sites are fixed)
```bash
grep -rl "INVENTORY-17" workflows/ && echo "FAIL: INVENTORY-17 markers still present" && exit 1 || true
```

**Check 4: Fail-closed path exists — `UNKNOWN_CHANNEL_IDENTITY` denyReason present**
```bash
jq -e '.. | strings | test("UNKNOWN_CHANNEL_IDENTITY")' workflows/W1_IN_WA.json
jq -e '.. | strings | test("UNKNOWN_CHANNEL_IDENTITY")' workflows/W2_IN_IG.json
jq -e '.. | strings | test("UNKNOWN_CHANNEL_IDENTITY")' workflows/W3_IN_MSG.json
```

**Check 5: W0_MODULE_GUARD has no `|| 'default'` on tenant_id line**
```bash
jq -e '.nodes[] | select(.name == "Module Guard") | .parameters.jsCode | test("tenant_id.*\\|\\|.*default") | not' \
  workflows/W0_MODULE_GUARD.json
```

### SQL-Level CI Assertions (n8n DB)

Extend `phase-16-assertions.yml` (or create `phase-17-assertions.yml`) with a job that:
1. Applies `db/bootstrap.sql` + `db/migrations/2026-06-20_channel_identities.sql` to an ephemeral Postgres
2. Asserts a known CI sentinel identity resolves:
```sql
DO $$
DECLARE v_tenant_id uuid; v_restaurant_id uuid;
BEGIN
  SELECT tenant_id, restaurant_id
  INTO v_tenant_id, v_restaurant_id
  FROM channel_identities
  WHERE channel = 'whatsapp'
    AND identity = 'CI_WA_PHONE_NUMBER_ID'
    AND is_active = true
  LIMIT 1;
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: known identity CI_WA_PHONE_NUMBER_ID did not resolve';
  END IF;
  IF v_tenant_id <> '00000000-0000-0000-0000-000000000001'::uuid THEN
    RAISE EXCEPTION 'FAIL: resolved to wrong tenant: %', v_tenant_id;
  END IF;
  RAISE NOTICE 'PASS: CI_WA_PHONE_NUMBER_ID resolves to correct tenant %', v_tenant_id;
END $$;
```
3. Asserts an unknown identity returns zero rows:
```sql
DO $$
DECLARE v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM channel_identities
  WHERE channel = 'whatsapp'
    AND identity = 'UNKNOWN_RANDOM_ID_XYZ'
    AND is_active = true;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: unknown identity resolved — should be 0 rows, got %', v_count;
  END IF;
  RAISE NOTICE 'PASS: unknown identity returns 0 rows (fail-closed behavior verified)';
END $$;
```

---

## 6. VPS Boundary

The local deliverables for Phase 17 are:
1. Modified `workflows/W1_IN_WA.json` — resolver node + fail-closed path + fallback removed
2. Modified `workflows/W2_IN_IG.json` — resolver node + fail-closed path + hardcoded UUID removed
3. Modified `workflows/W3_IN_MSG.json` — resolver node + fail-closed path + hardcoded UUID removed
4. Modified `workflows/W0_MODULE_GUARD.json` — `|| $env.DEFAULT_TENANT_ID || 'default'` removed, fail-closed guard added
5. Modified `workflows/W_DRIVER_ONBOARDING.json` — UUID literal fallback removed from `queryParams`
6. Updated `docs/adr/0002-tenant-id-fallback-inventory.md` — sites #2, #3, #4 marked REMOVED
7. `db/ci-assertions/17-tenant-resolution.sql` — SQL assertion file
8. `.github/workflows/phase-17-assertions.yml` — structural + SQL CI job

**🔴 VPS deferred:** Importing the updated workflow JSONs into production n8n via the n8n UI or API import. This is deferred to a prod-connected session per ROADMAP.md Phase 17 success criteria item 1 (`🔴 VPS` sub-step).

---

## Standard Stack

### Core (all already in repo, no new installs)

| Node Type | Version | Purpose | Source |
|-----------|---------|---------|--------|
| `n8n-nodes-base.postgres` | typeVersion: 2 | Channel identity lookup via `channel_identities` | Already used by `B0 - Resolve Client (DB)` in W1/W2/W3 |
| `n8n-nodes-base.code` | typeVersion: 2 | Auth context JS — reads resolver output, sets `denyReason` | Already used by `B0 - Apply Auth Context` |
| `n8n-nodes-base.if` | typeVersion: 2 | `B0 - Token OK?` — routes deny path | Already present |
| `postgres-main` credential | — | n8n DB connection (same credential as all existing Postgres nodes) | Confirmed: `"id": "postgres-main"` in `W1_IN_WA.json` node `B1a - Log Admin Access Attempt` |

**Installation:** None. No new packages, no new credentials to create (the planner instructs: use credential id `"postgres-main"`, name `"postgres-main"`).

---

## Architecture Patterns

### Existing Node Flow in W1_IN_WA (representative)

```
IN - Webhook
  → B0 - Parse & Canonicalize          # parses phone_number_id → inbound_envelope.meta.phone_number_id
  → B0 - Signature OK? (IF)
  → RESP - 200 ACK / RESP - 401 Sig
  → B0 - Contract Valid? (IF)
  → B0 - Resolve Client (DB)           # api_client token lookup: returns matched, tenant_id, restaurant_id
  → [NEW] B0 - Resolve Channel Identity (DB)  # channel_identities lookup: returns ci_tenant_id, ci_restaurant_id
  → [NEW] B0 - Map Channel Identity Result    # Code shim: namespaces resolver result
  → B0 - Apply Auth Context            # MODIFIED: uses ci_tenant_id/ci_restaurant_id; denyReason='UNKNOWN_CHANNEL_IDENTITY'
  → B0 - Seal Tenant Context
  → B0 - Token OK? (IF)               # FALSE branch: B0 - Log Deny (DB) → END - Drop/Done
  → B0 - Module Guard
  → ...
```

### Pattern: Channel-Identity Resolution Rung

**What:** A Postgres node that queries `channel_identities WHERE channel=$1 AND identity=$2 AND is_active=true`.
**When to use:** In inbound adapter `B0` sequences, immediately after `B0 - Resolve Client (DB)`, before the Code node that determines `tenantId`.
**Credential:** `postgres-main` (same DB as all other n8n-side Postgres nodes).

### Pattern: Fail-Closed on No-Match

**What:** If resolver returns null columns (no row), `B0 - Apply Auth Context` sets `authMode = 'deny'`, `denyReason = 'UNKNOWN_CHANNEL_IDENTITY'`. The existing `B0 - Token OK?` IF node routes to `B0 - Log Deny (DB)` and then `END - Drop/Done`. No new IF node needed — the existing deny path handles it.

### Anti-Patterns to Avoid

- **Chaining `|| 'default'` after `ciTenantId`** — this defeats the fail-closed intent. If `ciTenantId` is empty string/null, the auth mode must be `'deny'`, not a fallback.
- **Using `continueOnFail: true` on the resolver Postgres node** — if the DB is unreachable, the resolver returns no row → auth mode becomes `'deny'` (correct; fail closed). Do NOT add `continueOnFail: true` on the identity resolver node (unlike the Redis nodes which use `continueOnFail: true` because a Redis miss is recoverable — a DB miss here is a hard security boundary).
- **Adding the resolver node AFTER `B0 - Seal Tenant Context`** — the seal must occur on the already-resolved `tenant_context`. The resolver must precede the Apply node, which precedes the Seal node.
- **Skipping the Code shim for namespace isolation** — W2/W3 already output `tenant_id`/`restaurant_id` from `B0 - Resolve Client (DB)`, and the new resolver also outputs the same column names. Without a namespace shim, the api_client path and channel_identities path cannot be distinguished in `B0 - Apply Auth Context`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Channel-to-tenant routing lookup | A custom KV cache, env vars map, or in-memory table | `channel_identities` Postgres table (already exists from Phase 16) | The table has PK constraint, FKs, `is_active`, is seeded, and has an index on `tenant_id`. Already the designated Phase 17 lookup target per ADR and ROADMAP. |
| Auth failure parking | A custom "dead letter" workflow or Redis queue | Existing `B0 - Log Deny (DB)` → `END - Drop/Done` pattern | Already used for signature failures, scope failures, contract failures. Consistent, proven, DB-durable. |
| Cross-DB lookup to Strapi | An HTTP call to Strapi to resolve tenant | `channel_identities` in n8n DB | Same DB as `api_clients`/`tenants`/`restaurants` — no cross-DB hop, no Strapi dependency, much faster. |

---

## Common Pitfalls

### Pitfall 1: Resolver Postgres Node Returns Empty-Not-Null for No-Match

**What goes wrong:** When a `SELECT ... LIMIT 1` returns zero rows, the n8n Postgres node (typeVersion 2) returns an item with null values for the selected columns — NOT an error. If `B0 - Apply Auth Context` reads `$json.tenant_id` after the resolver, it gets `null`, and `null || 'default'` (if any default expression remains) silently falls through to the wrong tenant.

**How to avoid:** The Code shim explicitly assigns `ci_tenant_id = row.tenant_id || null` and sets a `ci_resolved` boolean. The Apply node checks `const ciResolved = !!(ciTenantId && ciRestaurantId)` — an empty string or null makes this `false` without any `||` fallback.

### Pitfall 2: W2/W3 Have a Duplicate `const metaSigValid` Declaration Bug

**What goes wrong:** In W2_IN_IG and W3_IN_MSG, `B0 - Apply Auth Context` declares `const metaSigValid` twice — once from `$env` at the start and once from `e._auth?.metaSigValid` later. This is a latent JS error (duplicate `const` in same scope throws `SyntaxError: Identifier 'metaSigValid' has already been declared`). n8n's Code node may silently handle this or throw at runtime.

**How to avoid:** The Phase 17 rewrite of `B0 - Apply Auth Context` in W2/W3 eliminates this bug by restructuring the variable declarations.

### Pitfall 3: `conversationKey` is Built Before `tenantId` is Resolved

**What goes wrong:** `conversationKey = tenantId + ':' + restaurantId + ':' + e.channel + ':' + e.userId`. If `tenantId` is `''` (empty, deny path), `conversationKey` is `':channel:userId'` which is malformed. The `B0 - Idempotency (DB)` node later inserts with this key — but it's after `B0 - Token OK?` which blocks the deny path.

**How to avoid:** The deny path never reaches `B0 - Idempotency (DB)`. However, ensure `conversationKey` defaults to `''` on deny (not a malformed string), as `B0 - Log Deny (DB)` passes it as `$json.conversationKey` (which is `null` / `''` on deny — the existing INSERT passes `null, null, null` for the first three params which is correct).

### Pitfall 4: The `phone_number_id` May Be Empty on Legacy/Test Payloads

**What goes wrong:** Legacy format payloads (not Meta-native) don't have `inbound_envelope.meta.phone_number_id`. The resolver gets `identity = ''` → no match → deny. This would break legacy integration tests.

**How to avoid:** The fix for the `meta_signature` auth mode already handles this: if `matched = true` (api_client token), the resolver result is irrelevant — api_client path still uses `e.tenant_id`. The channel_identities resolver is only the fallback path for Meta channels. For legacy payload format (which goes through `buildEnvelopeLegacy()`), the `phone_number_id` field is absent from `meta`. The resolver returns no match → deny. This is correct — legacy format without an api_client token should deny. If there is a real legacy compatibility need, it should be gated behind `SINGLE_TENANT_MODE` env var as documented in ROADMAP Phase 17 success criterion 4.

### Pitfall 5: W_DRIVER_ONBOARDING Has No Inbound Identity Signal

**What goes wrong:** W_DRIVER_ONBOARDING is triggered by Strapi, not Meta. It doesn't have a `channel_identities` lookup to perform. The fix is simpler — remove the UUID hardcode from the INSERT. But if `$json.tenant_id` is absent in the Strapi webhook payload, the INSERT fails with a NOT NULL error.

**How to avoid:** This is the correct fail-closed behavior for W_DRIVER_ONBOARDING. Document that Strapi must include `tenant_id`/`restaurant_id` in the webhook payload. If Strapi webhooks don't carry them, add a lookup against Strapi's API (but that's Phase 18 scope). For Phase 17, removing the hardcode and letting the NOT NULL constraint enforce correctness is sufficient.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash + psql + jq (same as Phase 15/16 CI pattern) |
| Config file | `.github/workflows/phase-17-assertions.yml` (new, to be created in Wave 0) |
| Quick run command | `jq -e '.nodes[] | select(.name == "B0 - Resolve Channel Identity (DB)")' workflows/W1_IN_WA.json` |
| Full suite command | `act pull_request -W .github/workflows/phase-17-assertions.yml` (or push to PR) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEN-03 | Resolver node exists in W1/W2/W3 | Structural (jq) | `jq -e '.nodes[] \| select(.name == "B0 - Resolve Channel Identity (DB)")' workflows/W1_IN_WA.json` | ❌ Wave 0 |
| TEN-03 | No `\|\| 'default'` / `DEFAULT_TENANT_ID` fallback remains on tenant path in W0/W1/W_DRIVER | Structural (grep) | `! grep -q "DEFAULT_TENANT_ID\||| 'default'" workflows/W0_MODULE_GUARD.json workflows/W1_IN_WA.json workflows/W_DRIVER_ONBOARDING.json` | ❌ Wave 0 |
| TEN-03 | `UNKNOWN_CHANNEL_IDENTITY` denyReason present in W1/W2/W3 JS | Structural (jq) | `jq -e '.. \| strings \| test("UNKNOWN_CHANNEL_IDENTITY")' workflows/W1_IN_WA.json` | ❌ Wave 0 |
| TEN-03 | No `INVENTORY-17` markers remain in workflows/ | Structural (grep) | `! grep -rl "INVENTORY-17" workflows/` | ❌ Wave 0 |
| TEN-03 | Known CI identity (CI_WA_PHONE_NUMBER_ID) resolves to correct tenant | SQL (psql) | `psql ... -f db/ci-assertions/17-tenant-resolution.sql` | ❌ Wave 0 |
| TEN-03 | Unknown identity returns 0 rows (fail-closed) | SQL (psql) | `psql ... -f db/ci-assertions/17-tenant-resolution.sql` (same file, second DO block) | ❌ Wave 0 |
| TEN-03 | `B0 - Apply Auth Context` in W2_IN_IG no longer has duplicate `const metaSigValid` | Structural (jq/grep) | `jq '.nodes[] \| select(.name == "B0 - Apply Auth Context") \| .parameters.jsCode' workflows/W2_IN_IG.json \| grep -c "const metaSigValid"` (expect: 1) | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** Run jq structural checks on modified workflow JSON files
- **Per wave merge:** Full `phase-17-assertions.yml` suite (structural + SQL)
- **Phase gate:** Full suite green + no `INVENTORY-17` markers remain before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `.github/workflows/phase-17-assertions.yml` — CI gate for structural + SQL assertions
- [ ] `db/ci-assertions/17-tenant-resolution.sql` — SQL DO-blocks asserting known identity resolves, unknown returns 0 rows

*(No new framework install needed — same `jq` + `psql` toolchain as Phase 15/16)*

---

## State of the Art

| Old Approach | Current Approach (Phase 17) | When Changed | Impact |
|---|---|---|---|
| `tenantId = envDefaultTenantId \|\| fallbackTenantId` for Meta channels | `tenantId = ciTenantId` from `channel_identities` lookup; no match → deny | Phase 17 | An unknown phone number can no longer silently route to a default tenant |
| `tenantId = '00000000-0000-0000-0000-000000000001'` hardcoded in W2/W3 | Same `channel_identities` lookup; no hardcode | Phase 17 | IG/MSG channels can serve multiple tenants without code changes |
| `|| $env.DEFAULT_TENANT_ID \|\| 'default'` in W0_MODULE_GUARD | Guard fails closed if `tenant_id` not provided by caller | Phase 17 | Defense-in-depth: guard cannot accidentally allow `'default'` tenant |
| UUID literal fallback in W_DRIVER_ONBOARDING | No fallback; NOT NULL constraint enforces correctness | Phase 17 | Strapi must supply tenant context; data errors are loud |

---

## Open Questions

1. **SINGLE_TENANT_MODE compatibility flag** (ROADMAP success criterion 4)
   - What we know: The roadmap says "any legacy single-tenant fallback is gated behind one explicit, documented flag (e.g. `SINGLE_TENANT_MODE`)".
   - What's unclear: Should Phase 17 actually implement a `SINGLE_TENANT_MODE` env var that re-enables the `DEFAULT_TENANT_ID` fallback, or simply remove all fallbacks and treat this as fully multi-tenant?
   - Recommendation: Implement `SINGLE_TENANT_MODE` as an explicit env var. If `SINGLE_TENANT_MODE=true` AND `ciResolved=false`, fall back to `DEFAULT_TENANT_ID` with `authMode='legacy_single_tenant'`. This makes the single-tenant-mode a deliberate, logged decision. Default: `SINGLE_TENANT_MODE=false` → fail closed. The planner should create a plan task for this.

2. **W_DRIVER_ONBOARDING tenant derivation from Strapi payload**
   - What we know: The current Strapi webhook payload for driver-created does not clearly document whether `tenant_id`/`restaurant_id` are included.
   - What's unclear: Does the Strapi driver content type include `tenant_id` in its webhook payload (as a relation field)?
   - Recommendation: Phase 17 removes the fallback and logs a clear error if the fields are absent. If Strapi webhook payloads don't include them, this is a Phase 18 concern (Strapi data-plane scoping). Accept that W_DRIVER_ONBOARDING may fail for now on the fix until Phase 18 wires the context properly.

---

## Sources

### Primary (HIGH confidence)
- `workflows/W1_IN_WA.json` — direct read; node `"B0 - Apply Auth Context"` id `80046a7e-854b-4e57-b467-6f04fdc9f0ad`, `__inventory_15` annotation, `jsCode` for all fallback constructs
- `workflows/W2_IN_IG.json` — direct read; node `"B0 - Apply Auth Context"` id `1d94ff21-11e5-4aff-b5f9-946d84ab576b`, hardcoded UUID fallbacks confirmed
- `workflows/W3_IN_MSG.json` — direct read; node `"B0 - Apply Auth Context"` id `0aba4d61-8e1b-4f65-b17b-a02515c8685f`, same hardcoded UUID pattern
- `workflows/W0_MODULE_GUARD.json` — node `"Module Guard"`, `|| $env.DEFAULT_TENANT_ID || 'default'` confirmed at line ~L21 of jsCode, `__inventory_15` annotation present
- `workflows/W_DRIVER_ONBOARDING.json` — node `"Ensure Customer Profile"` id `e6a4b12c-3d4f-4e5a-8b6c-7d8e9f0a1b2c`, `queryParams` fallback confirmed, `__inventory_15` annotation present
- `db/migrations/2026-06-20_channel_identities.sql` — table schema confirmed: `PRIMARY KEY (channel, identity)`, `is_active boolean NOT NULL DEFAULT true`, FKs to `tenants`/`restaurants`, 4 CI sentinel rows
- `docs/adr/0002-tenant-id-fallback-inventory.md` — exact inventory of 5 occurrences, INVENTORY-17 disposition for sites #2, #3, #4
- `docs/adr/0001-canonical-tenant-key.md` — canonical UUID `00000000-0000-0000-0000-000000000001` for CI/dev
- `.github/workflows/phase-15-assertions.yml`, `phase-16-assertions.yml` — CI assertion pattern (psql + DO blocks)

### Secondary (MEDIUM confidence)
- `.planning/research/SUMMARY.md` — architecture recommendation: "one new resolution rung", `postgres-main` credential pattern, `channel_identities` in n8n DB, no cross-DB hop
- `.planning/ROADMAP.md` Phase 17 success criteria — verified against findings
- `.planning/REQUIREMENTS.md` TEN-03 — exact requirement text confirms fail-closed behavior
- `.claude/skills/11_workflow_governance/SKILL.md` — integrity gate rules (JSON valid, no embedded secrets, error handling present)
- `.claude/skills/04_n8n_queue_sre/SKILL.md` — queue-mode non-negotiables: fast ACK, idempotency gate, no duplicate side effects

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all node types and credential pattern confirmed by direct read of existing workflow JSON files
- Architecture: HIGH — exact node IDs, JS code, insertion points, and connection wiring all read directly from source files
- Pitfalls: HIGH — grounded in actual code bugs found (duplicate `const metaSigValid`), actual null-return behavior of n8n Postgres nodes, and `tenant_context` seal ordering
- SQL: HIGH — `channel_identities` schema confirmed from migration file; SQL pattern mirrors existing `B0 - Resolve Client (DB)` query

**Research date:** 2026-06-20
**Valid until:** 2026-07-20 (stable — workflow JSON and table schema are static artifacts; n8n 2.9.4 Postgres node behavior is well-documented)

---

## RESEARCH COMPLETE

**Phase:** 17 - Inbound Tenant Derivation (Fail-Closed)
**Confidence:** HIGH

### Key Findings

- **Resolver mechanism:** A `n8n-nodes-base.postgres` node (`typeVersion: 2`, credential `postgres-main`) inserted between `B0 - Resolve Client (DB)` and `B0 - Apply Auth Context` in W1/W2/W3. SQL: `SELECT tenant_id::text, restaurant_id::text FROM channel_identities WHERE channel = $1 AND identity = $2 AND is_active = true LIMIT 1`. A Code shim node namespaces the result as `ci_tenant_id` / `ci_restaurant_id` / `ci_resolved` to avoid collision with the api_client path columns.

- **Identity extraction per channel:** W1_IN_WA reads `$json.inbound_envelope?.meta?.phone_number_id` (WhatsApp `value.metadata.phone_number_id`, parsed by `B0 - Parse & Canonicalize`). W2_IN_IG and W3_IN_MSG read `$json.inbound_envelope?.meta?.recipient_id` (parsed from `messaging.recipient?.id` in their respective parse nodes).

- **Fail-closed / park pattern:** No new node required for the primary deny path. Setting `denyReason = 'UNKNOWN_CHANNEL_IDENTITY'` in `B0 - Apply Auth Context` routes through the existing `B0 - Token OK?` → `B0 - Log Deny (DB)` → `END - Drop/Done` chain. The security event is written to `security_events.event_type = 'UNKNOWN_CHANNEL_IDENTITY'` with `severity = 'HIGH'`. The external caller (Meta) always receives 200 (fast-ACK pattern in W1; `RESP - 200 OK` at `END - Drop/Done` in W2/W3).

- **Three INVENTORY-17 fallbacks to remove:** (a) `W0_MODULE_GUARD.json` node `"Module Guard"` — `|| $env.DEFAULT_TENANT_ID || 'default'` replaced with explicit empty-check + fail-closed return; (b) `W1_IN_WA.json` node `"B0 - Apply Auth Context"` id `80046a7e-...` — entire `defaultTenantId`/`fallbackTenantId` construct removed, `meta_signature`/`legacy_shared` branches use `ciTenantId`; (c) `W_DRIVER_ONBOARDING.json` node `"Ensure Customer Profile"` id `e6a4b12c-...` — `|| $env.DEFAULT_TENANT_ID || '00000000-...-000001'` removed from `queryParams`. W2_IN_IG and W3_IN_MSG hardcoded UUID branches (not formally INVENTORY-17 tagged but same issue) are also removed. All `__inventory_15` annotation keys removed once sites are fixed; `docs/adr/0002` occurrences #2, #3, #4 updated to `REMOVED (Phase 17)`.

- **Latent bug discovered:** W2_IN_IG and W3_IN_MSG `B0 - Apply Auth Context` nodes have a duplicate `const metaSigValid` declaration in the same JS scope — a `SyntaxError` waiting to surface. Phase 17 rewrite of these nodes eliminates the bug.

- **No new libraries, no new credentials, no VPS work now:** Only workflow JSON files and one new CI YAML + SQL assertion file. 🔴 VPS: importing updated workflows is deferred to prod-connected session.

### File Created
`.planning/phases/17-inbound-tenant-derivation-fail-closed/17-RESEARCH.md`

### Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Standard Stack | HIGH | Credential id `postgres-main`, node type `n8n-nodes-base.postgres` typeVersion 2 confirmed by direct file read |
| Architecture | HIGH | Exact node IDs, JS code, connection wiring read from W1/W2/W3/W0/W_DRIVER source files |
| Pitfalls | HIGH | Duplicate `const metaSigValid` bug found by reading actual code; null-return behavior is n8n Postgres node documented behavior |
| Fail-closed path | HIGH | Existing `B0 - Token OK?` → `B0 - Log Deny (DB)` → `END - Drop/Done` chain confirmed present in all three adapters |
| SQL | HIGH | Table schema from migration file; columns and constraint names exact |

### Open Questions

1. Whether `SINGLE_TENANT_MODE` flag should be implemented as an env var or omitted (planner decision)
2. Whether Strapi driver webhook payload includes `tenant_id` / `restaurant_id` (affects W_DRIVER_ONBOARDING fix correctness)

### Ready for Planning
Research complete. Planner can now create three PLAN.md files:
- `17-01-PLAN.md` — channel_identities resolver rung in W1/W2/W3 `B0 - Apply Auth Context` + W0_MODULE_GUARD fallback removal
- `17-02-PLAN.md` — fail-closed `UNKNOWN_CHANNEL_IDENTITY` path + security_events write + W_DRIVER_ONBOARDING fallback removal + ADR 0002 update
- `17-03-PLAN.md` — CI structural assertions (jq) + SQL assertions (17-tenant-resolution.sql) + phase-17-assertions.yml
