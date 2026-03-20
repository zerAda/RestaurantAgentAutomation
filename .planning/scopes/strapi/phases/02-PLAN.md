# Phase 1, Plan 02 — Fix platform-setting Enum Default

**Phase:** 01-stability
**Plan:** 02
**Requirements:** STBL-02
**Wave:** 1 (parallel with Plan 01 — touches different files, no dependency)
**Autonomous:** true

---

## Objective

Fix the `platform-setting` content type schema so that the `category` field default is a valid enum value. The current default is `"ops"` which is not in the allowed set `["CORE","AI","SOCIAL","LOGISTICS","WEB_KIOSK","WEB_ADMIN","PAYMENT","SECURITY"]`.

**Impact of the bug:** Any n8n workflow or API call that creates a `platform-setting` entry without explicitly providing a `category` field receives a Strapi validation error. The admin panel form pre-populates with `"ops"` which is rejected on save.

**Fix:** Change `"default": "ops"` to `"default": "CORE"` in the schema JSON. This is a non-breaking change: the DB column (`category`) allows NULLs for existing rows and the column type is VARCHAR — no migration is needed for existing data. New rows created without a category will receive `"CORE"`.

**Rollback:** `git checkout project/inventory-cms/src/api/platform-setting/content-types/platform-setting/schema.json` — no database changes to roll back.

---

## Task 1 — Fix the enum default in platform-setting schema

**Files:**
- `project/inventory-cms/src/api/platform-setting/content-types/platform-setting/schema.json`

**Action:**

Read the current content of the file. It is a 51-line JSON file. The `category` attribute is at lines 30-44. The `"default": "ops"` value is on line 43.

Change:
```json
"default": "ops"
```

To:
```json
"default": "CORE"
```

The full `category` attribute block after the fix must be:
```json
"category": {
  "type": "enumeration",
  "enum": [
    "CORE",
    "AI",
    "SOCIAL",
    "LOGISTICS",
    "WEB_KIOSK",
    "WEB_ADMIN",
    "PAYMENT",
    "SECURITY"
  ],
  "required": true,
  "default": "CORE"
},
```

No other field in the schema file is modified.

**Acceptance criteria:**
- `schema.json` contains `"default": "CORE"` (not `"ops"`)
- `schema.json` is valid JSON (no syntax errors)
- The `enum` array is unchanged: still contains exactly the 8 values listed above

**Verify:**
```bash
python3 -c "import json; s=json.load(open('project/inventory-cms/src/api/platform-setting/content-types/platform-setting/schema.json')); d=s['attributes']['category']['default']; print('DEFAULT:', d); assert d == 'CORE', f'FAIL: default is {d}'; print('OK')"
```

---

## Task 2 — Validate schema against Strapi schema rules and run a compile check

**Files:** No files modified — verification only.

**Action:**

Step 1 — Validate that the schema is well-formed JSON and that `"default"` is one of the `"enum"` values:

```bash
python3 - <<'PYEOF'
import json, sys
path = "project/inventory-cms/src/api/platform-setting/content-types/platform-setting/schema.json"
with open(path) as f:
    schema = json.load(f)
cat = schema["attributes"]["category"]
default = cat["default"]
enum_vals = cat["enum"]
assert default in enum_vals, f"FAIL: default '{default}' not in enum {enum_vals}"
assert schema["kind"] == "collectionType", "FAIL: kind changed"
assert schema["attributes"]["key"]["required"] == True, "FAIL: key.required changed"
print(f"PASS: category default='{default}' is valid (enum={enum_vals})")
PYEOF
```

Step 2 — Run TypeScript no-emit compile from the CMS directory to confirm the schema change did not introduce any TypeScript type errors in dependent code:

```bash
cd project/inventory-cms && npx tsc --noEmit 2>&1 | grep -E "platform-setting|error TS" | head -10
echo "tsc exit: $?"
```

Zero errors is required.

Step 3 — Confirm the dist/ compiled version also reflects the fix (if dist/ is committed). Strapi reads from `dist/` in production (`strapi start`):

```bash
grep -r '"default": "ops"' project/inventory-cms/dist/ 2>/dev/null && echo "WARN: dist/ still has old default — rebuild needed" || echo "OK: dist/ clean"
```

If `dist/` still contains `"ops"`, the image must be rebuilt before deploying. Note this in the PATCHLOG entry.

**Acceptance criteria:**
- Python validation script exits 0 with `PASS` message
- `npx tsc --noEmit` exits with code 0
- `dist/` either contains `"CORE"` default or an explicit note is made that a rebuild is required

**Verify:**
```bash
grep '"default"' "project/inventory-cms/src/api/platform-setting/content-types/platform-setting/schema.json"
```
Expected output: `      "default": "CORE"`

---

## Task 3 — Add PATCHLOG entry and update ENV_REFERENCE if needed

**Files:**
- `project/PATCHLOG.md`

**Action:**

Read `project/PATCHLOG.md`. Append a new entry at the top of the file (before existing entries) using this format:

```markdown
## [DATE] — STBL-02: Fix platform-setting enum default

**What:** Changed `category` field default from `"ops"` (invalid) to `"CORE"` (valid) in
`src/api/platform-setting/content-types/platform-setting/schema.json`.

**Why:** Strapi validation was rejecting any `POST /api/platform-settings` request that did not
explicitly include a `category` field. The admin panel form pre-populated with `"ops"` which is
not in the allowed enum values `[CORE, AI, SOCIAL, LOGISTICS, WEB_KIOSK, WEB_ADMIN, PAYMENT, SECURITY]`.

**Risk:** Low. Non-breaking schema change. No existing rows are affected (NULL → CORE only for new
rows without an explicit category). No migration required.

**Rollback:** `git checkout project/inventory-cms/src/api/platform-setting/content-types/platform-setting/schema.json`
Then rebuild and redeploy CMS image.

**Files changed:**
- `project/inventory-cms/src/api/platform-setting/content-types/platform-setting/schema.json`
```

No ENV_REFERENCE.md changes are needed — this fix touches only a schema default value, no env vars are added or modified.

**Acceptance criteria:**
- `PATCHLOG.md` has a new entry at the top referencing STBL-02
- Entry includes what, why, risk, and rollback sections

**Verify:**
```bash
head -20 project/PATCHLOG.md
```

---

## End-to-End Acceptance Test

After both Plan 01 and Plan 02 complete, the following must hold:

**Route deduplication (from Plan 01):**
```bash
# Strapi startup logs show exactly one agent-chat route registration
docker logs current-cms-1 2>&1 | grep -c "POST /api/agent/chat"
# Expected: 1 (not 3)
```

**Enum fix (from Plan 02):**
```bash
# POST to platform-settings without category — should succeed with CORE default
curl -s -X POST http://127.0.0.1:1337/api/platform-settings \
  -H "Authorization: Bearer $STRAPI_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"data": {"key": "TEST_ENUM_FIX", "value": "test"}}' \
  | python3 -c "import sys,json; r=json.load(sys.stdin); cat=r['data']['attributes']['category']; print('category:', cat); assert cat == 'CORE', f'FAIL: {cat}'"
# Expected output: category: CORE
# Clean up after test:
# curl -s -X DELETE http://127.0.0.1:1337/api/platform-settings/<id> -H "Authorization: Bearer $STRAPI_API_TOKEN"
```

---

## Rollback Strategy

**For the enum fix only:**
```bash
git checkout project/inventory-cms/src/api/platform-setting/content-types/platform-setting/schema.json
```
Then rebuild and redeploy. No database changes required — the default only affects new rows.

**For both Plan 01 and Plan 02 together:**
```bash
git revert HEAD  # or git checkout the changed files individually
# Rebuild and push image via CI
```

---

## Success Criteria

- `platform-setting` schema has `"default": "CORE"` (valid enum member)
- `POST /api/platform-settings` without `category` field returns 201 with `category: "CORE"`
- Zero TypeScript compilation errors in `project/inventory-cms/`
- `PATCHLOG.md` updated with STBL-02 entry
- CMS image rebuilds cleanly with updated schema
