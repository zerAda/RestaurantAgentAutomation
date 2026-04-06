# SaaS Platform Hardening Report

**Date**: 2026-04-06  
**Scope**: Production security hardening + product segmentation + multi-tenant entitlements  
**Status**: ✅ Committed to `main`

---

## Executive Summary

This hardening pass transformed the RestaurantAgentAutomation monorepo from a monolithic demo into a product-segmented, multi-tenant SaaS platform. All P0 security vulnerabilities identified during the audit have been patched. The platform now has explicit module boundaries, tenant-level entitlements, and a workflow registry covering all 98 n8n workflows.

## Changes Delivered

### 🔴 P0 Security Fixes

| Issue | Fix | Files |
|-------|-----|-------|
| Production secrets in git | Removed `.env.production` from tracking, hardened `.gitignore` | `.gitignore`, `.env.production` |
| Fallback admin password `ChangeMeNow!` | Removed all fallback creds, production refuses to start without env vars | `inventory-cms/src/index.ts` |
| Unconditional password sync on restart | Removed force-sync that overwrote manual password changes | `inventory-cms/src/index.ts` |
| Duplicate `/agent/chat` route (auth:false) | Eliminated duplicate, kept only scoped-auth version | `system-config/routes/agent-chat.ts` |
| `/control-plane/status` publicly exposed | Split into `/health` (public, minimal) + `/status` (admin auth required) | `control-plane/routes/*.ts`, `controllers/*.ts` |
| SSE token in query string + `CORS: *` | Cookie-based auth primary, query-string deprecated, CORS restricted | `realtime/controllers/realtime.ts` |
| Kiosk secret baked in JS bundle | Removed `x-kiosk-secret` from client code | `kiosk-app/src/services/strapiClient.ts` |
| `platform-setting` invalid enum default | Fixed `"ops"` → `"CORE"` | `platform-setting/schema.json` |
| In-memory-only rate limiting | Hybrid Redis/memory rate limiter | `middlewares/auth-ratelimit.ts` |

### 📦 Product Segmentation

| Artifact | Description |
|----------|-------------|
| `config/workflow_registry.json` | 98 workflows classified by module, tier, trigger, exposure, auth |
| `config/product_modules.json` | 15 product modules with dependencies and rollout policies |
| `workflows/W0_MODULE_GUARD.json` | Shared sub-workflow for entitlement validation |

### 🏗️ Multi-Tenant Infrastructure

| Component | Description |
|-----------|-------------|
| `product-module` content type | Strapi collectionType for module definitions |
| `tenant-entitlement` content type | Per-tenant module activation with expiry & config overrides |
| DB migration | Unique constraints, indexes, and entitlement audit log |

### 🛡️ CI/CD

| Artifact | Description |
|----------|-------------|
| `.github/workflows/secret-scan.yml` | Gitleaks + custom pattern scanning on every PR |
| `tests/test_registry_validity.sh` | Cross-references registry with actual workflow files |

## Architecture After Hardening

```
┌─────────────────────────────────────────────────┐
│               OPERATOR PLANE                     │
│  admin-dashboard + AI agent (Stitch MCP UI)      │
│  ↕ Authenticated API calls                       │
├─────────────────────────────────────────────────┤
│               CONTROL PLANE (Strapi)             │
│  ┌──────────┐ ┌─────────────────┐ ┌───────────┐ │
│  │ product- │ │ tenant-         │ │ platform- │ │
│  │ module   │ │ entitlement     │ │ setting   │ │
│  └──────────┘ └─────────────────┘ └───────────┘ │
│  Auth: Scoped JWT │ Rate: Redis-backed           │
│  SSE: Cookie auth │ CORS: Restricted origins     │
├─────────────────────────────────────────────────┤
│               EXECUTION PLANE (n8n)              │
│  ┌─────────────────┐  ┌──────────────────────┐  │
│  │ W0_MODULE_GUARD  │──│ 98 classified         │  │
│  │ (entitlement     │  │ workflows in          │  │
│  │  gate)           │  │ 15 product modules    │  │
│  └─────────────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────┤
│               DATA PLANE                         │
│  PostgreSQL (tenant-isolated) │ Redis (sessions) │
│  entitlement_audit_log        │ rate limit keys  │
└─────────────────────────────────────────────────┘
```

## Immediate Action Required

> ⚠️ **Rotate ALL production secrets** — see `docs/SECRETS_ROTATION_REQUIRED.md`

## What's Staged (Not Yet Deployed)

- W0_MODULE_GUARD needs to be imported into n8n and wired to priority entrypoints
- Tenant entitlements need to be seeded for existing tenants
- Admin dashboard UI needs module-aware navigation (Stitch MCP)
- Kiosk app auth flow needs server-side session token implementation

## What's Deferred

- `config-version` content type (versionable config rollout)
- `secret-reference` content type (secret rotation tracking in Strapi)
- Full fail-closed mode for W0_MODULE_GUARD (currently fail-open)
- BFG Repo-Cleaner to purge secrets from git history
