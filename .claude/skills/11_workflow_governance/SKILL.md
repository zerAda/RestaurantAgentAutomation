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

# Workflow Governance (RESTO BOT)

## Current state

- **54 workflow JSON files** in `project/workflows/`
- Validated by integrity gate in CI (`integrity-gate.yml`)
- Deployed to n8n-main via volume mount or API import

## Naming conventions

- Prefix by domain: `inbound_`, `outbox_`, `order_`, `menu_`, `admin_`, `support_`, `fraud_`
- Suffix: `_v1`, `_v2` for versioned workflows
- No spaces in filenames; use underscores

## Structure requirements per workflow

- Must have a unique `name` field
- Must have error handling (error workflow configured)
- Webhook triggers must validate auth (X-API-Token or signature)
- No hardcoded secrets in workflow JSON (use env vars or credentials)
- Idempotency: dedupe check near ingestion point

## Strapi integration

- CMS content types accessed via Strapi REST API
- Strapi URL: `https://cms.srv1258231.hstgr.cloud`
- CORS: admin.*, kiosk.*, cms.* allowed origins
- Workflow nodes that call Strapi should use configurable base URL

## Tenant isolation (future-proofing)

- All workflows should use tenant_id where applicable
- Avoid hard-coding single-tenant assumptions
- Authorization layer extensible (token -> tenant scope)

## Integrity gate checks

- JSON valid and parseable
- Required fields present (name, nodes, connections)
- No embedded secrets or tokens
- Consistent naming conventions
- Error workflow configured

## MCP integration

- **n8n-mcp** server can list/create/update/execute workflows
- **strapi-mcp** server can manage CMS content types
- Use MCP tools for workflow management when available

## Key files

- `project/workflows/` (all 54 workflow JSON files)
- `project/.github/workflows/integrity-gate.yml`
- `project/schemas/` (JSON validation schemas)

## Required output

- Workflow diff with rationale
- Integrity gate compliance check
- Security review (no secrets, auth enforced)
- Tenant isolation assessment
