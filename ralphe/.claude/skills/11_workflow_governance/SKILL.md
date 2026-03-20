---
name: workflow_governance
description: Govern 54 n8n workflow JSON files - naming, structure, security checks, tenant isolation, integrity gate compliance.
when_to_use:
  - Adding or modifying workflow JSON files
  - Debugging integrity gate failures
  - Reviewing tenant isolation
  - Adding new Strapi nodes
  - Workflow import/export
---

# Workflow Governance

## Workflow inventory

- 54 JSON files in `workflows/`
- Naming conventions: `W<N>_<NAME>.json` (numbered) or `W_<NAME>.json` (feature-based)
- Validated by: `scripts/integrity_gate.sh`, `.github/workflows/workflow-validate.yml`

## Structural requirements (enforced by CI)

Every workflow JSON must have:

```json
{
  "name": "W<N>_<NAME>",
  "nodes": [...],
  "connections": {...}
}
```

- `.active` field is optional (null accepted)
- `.nodes` must be an array, `.connections` must be an object

## Security checks (integrity_gate.sh)

### Inbound workflows (W1_IN_WA, W2_IN_IG, W3_IN_MSG)

1. `B0 - Parse & Canonicalize` must contain `ALLOW_QUERY_TOKEN` gating
2. `B0 - Token OK?` must enforce `scopeOk` (`={{$json._auth.scopeOk}}`)
3. `B0 - Log Deny (DB)` must parameterize `event_type` with `$6`
4. `B0 - Contract Valid?` node must exist
5. `RESP - 200` and `RESP - 400/401` response nodes must exist
6. `IN - Webhook` must use `responseMode: responseNode`

### W1_IN_WA specific

7. `B1a - Admin Access Validator (SECURED)` node must exist
8. `B1 - Has Media to Fetch?` must route to validator (check `main[][]` not `main[0][]`)

### All Strapi nodes (P0 tenant isolation)

9. Every `n8n-nodes-base.strapi` node must have `filters.restaurant_id.$eq` containing `tenant_context`
10. The jq check uses `while IFS= read -r` loop (handles multi-word node names)

## Common integrity gate failures and fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `bypass detected in B1` | jq path uses `main[0][]` | Change to `main[][]` |
| `Strapi filter MUST use tenant_context` | Missing `restaurant_id.$eq` filter | Add `"filters": {"restaurant_id": {"$eq": "={{ $json.tenant_context?.restaurant_id }}"}}` |
| `Missing required fields` | Workflow missing `.active` field | Ensure validator accepts null `.active` |
| `Does not match naming convention` | File named without W prefix | Use `W<N>_` or `W_` prefix |
| `Cannot index string with "$eq"` | `restaurant_id` is string not object | Wrap in `{"$eq": "..."}` structure |

## Adding a new Strapi node checklist

1. Add the node with operation and collection
2. Add `filters.restaurant_id.$eq` with `tenant_context` reference
3. Use `{"$eq": "={{ $json.tenant_context?.restaurant_id }}"}` (object, not string)
4. Run `make integrity` locally to verify
5. Check CI passes after push

## Deliverables

- Workflow diff (valid JSON, passes `jq -e` validation)
- Integrity gate passes locally (`make integrity`)
- Tenant isolation verified for all Strapi nodes
- CI green for `workflow-validate.yml` and `ci.yml` integrity gate job
