# Product Segmentation Architecture

**Version**: 1.0.0  
**Last Updated**: 2026-04-06  
**Status**: Implemented — Guard wiring active, entitlement bootstrap seeding active

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    OPERATOR PLANE                                │
│         Admin Dashboard  +  AI Agent (bounded actions)           │
│              ↕ Strapi API (JWT auth)                            │
├─────────────────────────────────────────────────────────────────┤
│                    CONTROL PLANE (Strapi)                        │
│  ┌──────────────┬──────────────────┬─────────────────────┐      │
│  │ product-     │ tenant-          │ platform-setting    │      │
│  │   module     │   entitlement    │ system-config       │      │
│  │ (registry)   │ (per-tenant)     │ (runtime defaults)  │      │
│  └──────────────┴──────────────────┴─────────────────────┘      │
├─────────────────────────────────────────────────────────────────┤
│                   EXECUTION PLANE (n8n)                          │
│  ┌───────────────────────────────────────────────────────┐      │
│  │  W0_MODULE_GUARD (Fail-Closed entitlement gate)       │      │
│  │       ↓                                               │      │
│  │  Webhook → Guard → IF(allowed) → Business Logic       │      │
│  │                  → IF(!allowed) → 403 Forbidden        │      │
│  └───────────────────────────────────────────────────────┘      │
│  98 workflows across 15 product modules                          │
├─────────────────────────────────────────────────────────────────┤
│                    DATA PLANE                                    │
│            PostgreSQL + Redis + Ollama (LLM)                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Product Module Hierarchy

### Tier 1: Shared Core (always-on)
- **`platform_runtime`** — 18 workflows. Config reader, Redis helper, Meta verify, outbox, DLQ, health checks, metrics, audit. Cannot be disabled.

### Tier 2: Product Core (always-on for sold products)
- **`order_bot_core`** — 7 workflows. The base conversational commerce engine. Cart, router, FAQ, delivery quote, admin orders.

### Tier 3: Channel Packs (independently activatable)
- **`channel_whatsapp`** — 4 workflows. Guard-gated at `W1_IN_WA`.
- **`channel_instagram`** — 2 workflows. Guard-gated at `W2_IN_IG`.
- **`channel_messenger`** — 2 workflows. Guard-gated at `W3_IN_MSG`.
- **`channel_tiktok`** — 3 workflows. Guard-gated at `W1_IN_TIKTOK`.

### Tier 4: Add-on Packs (optional)
- **`payment`** — 3 workflows. Chargily, callback, finalizer.
- **`delivery_dispatch`** — 15 workflows. Drivers, logistics, surge, weather.
- **`inventory`** — 6 workflows. Orchestration, sync, alerts, validation.
- **`kiosk_instore`** — 5 workflows. Kiosk ordering, QR, gamification, printing.
- **`voice`** — 4 workflows. STT, TTS, voice call init, confirmation.
- **`loyalty_crm`** — 5 workflows. Loyalty, abandonment, win-back, upsell, reviews.
- **`growth_marketing`** — 14 workflows. Funnels, AI, content, ads, campaigns.
- **`admin_ai_intelligence`** — 6 workflows. AI agent, monitor, proactive agent, cortex, omniscient.

### Tier 5: Experimental (disabled by default)
- **`experimental`** — 4 workflows. Stale, duplicated, or partially integrated.

---

## Entitlement Model

### How It Works

1. **Strapi holds the registry**: `product-module` defines what modules exist. `tenant-entitlement` maps tenants to modules.
2. **n8n enforces at runtime**: Every public/external webhook calls `W0_MODULE_GUARD` which queries Strapi for the tenant's entitlement.
3. **Fail-Closed**: If Strapi is unreachable or the entitlement check errors, the guard returns `allowed: false` (403 Forbidden).

### Guard Decision Flow

```
Inbound Request
  → Extract tenantId (from webhook body, phone number, or header)
  → Extract moduleKey (from workflow metadata)
  → Call W0_MODULE_GUARD
    → GET /api/tenant-entitlements?tenant_id=X&module_key=Y
    → IF found AND enabled → allowed: true
    → IF not found OR disabled → allowed: false
    → IF error (Strapi down) → allowed: false (FAILCLOSED)
  → IF allowed: proceed to business logic
  → IF denied: return 403 Forbidden
```

### Guarded Entrypoints (7 priority adapters)

| Workflow | Module | Public Path |
| :--- | :--- | :--- |
| W1_IN_WA | channel_whatsapp | /v1/inbound/whatsapp |
| W2_IN_IG | channel_instagram | /v1/inbound/instagram |
| W3_IN_MSG | channel_messenger | /v1/inbound/messenger |
| W1_IN_TIKTOK | channel_tiktok | /tiktok-webhook |
| W30_VOICE_CALL_INIT | voice | /v1/voice/inbound-call |
| W_KIOSK_ORDER | kiosk_instore | /kiosk-order |
| W_ORDER_FINALIZER | payment | /order/finalize |

---

## Bootstrap Seeding

On first Strapi start, `saas-entitlements.ts` seeds:
1. All 15 product modules into `product-module` collection
2. Default tenant entitlements enabling all non-experimental modules

This ensures backward compatibility — an existing single-restaurant deployment will continue to work without manual entitlement configuration.

---

## Security Model

| Layer | Protection | Status |
| :--- | :--- | :--- |
| n8n Guard | W0_MODULE_GUARD (Fail-Closed) | ✅ Active |
| Strapi Auth | JWT-scoped routes, admin-only diagnostics | ✅ Active |
| Rate Limiting | Hybrid Redis/memory (auth: 5/5min, API: 300/min) | ✅ Active |
| Secret Management | `.gitignore` patterns, no tracked `.env.*` | ✅ Active |
| CORS | Restricted to `ADMIN_DASHBOARD_ORIGINS` | ✅ Active |
| SSE Auth | Cookie-based primary, query-token deprecated | ✅ Active |

---

## File Map

| File | Purpose |
| :--- | :--- |
| `config/product_modules.json` | Module definitions with tiers, dependencies, workflow bindings |
| `config/workflow_registry.json` | Per-workflow classification (98 entries) |
| `workflows/W0_MODULE_GUARD.json` | n8n shared guard workflow |
| `inventory-cms/src/api/product-module/` | Strapi content type for module registry |
| `inventory-cms/src/api/tenant-entitlement/` | Strapi content type for tenant entitlements |
| `inventory-cms/src/bootstrap-seeds/saas-entitlements.ts` | Bootstrap seeder |
| `docs/WORKFLOW_INVENTORY.md` | Human-readable inventory |
| `docs/PRODUCT_SEGMENTATION.md` | This document |
| `docs/SAAS_HARDENING_REPORT.md` | Session-by-session hardening report |
