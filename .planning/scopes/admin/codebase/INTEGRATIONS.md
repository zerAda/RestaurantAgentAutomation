# Admin Dashboard — External Integrations

**Analysis Date:** 2026-03-20
**Scope:** `project/admin-dashboard/`

---

## Overview

The admin dashboard integrates with exactly two backends:
1. **Strapi CMS** — primary backend for all data (auth, orders, inventory, config, AI agent)
2. **n8n** — indirectly, via Strapi custom controllers that proxy to n8n webhooks

The browser never calls n8n directly. All n8n interaction is mediated through Strapi endpoints.

---

## Auth Flow — Strapi Users-Permissions JWT

**Endpoint:** `POST ${VITE_STRAPI_URL}/api/auth/local`

**Login sequence in `src/services/authService.ts`:**
```typescript
// Step 1: authenticate
POST /api/auth/local
body: { identifier: email, password }
→ { jwt: '...', user: { id, username, email } }

// Step 2: fetch full user with role (for RBAC)
GET /api/users/me?populate=role
headers: { Authorization: `Bearer ${jwt}` }
→ { id, username, email, role: { name, type } }

// Step 3: store
sessionStorage.setItem('admin_jwt', jwt)
sessionStorage.setItem('admin_user', JSON.stringify(user))
sessionStorage.setItem('admin_jwt_expiry', String(Date.now() + 86400000))
```

**Token usage** (`src/services/strapiClient.ts`):
- Every request gets `Authorization: Bearer <jwt>` header
- Token read from `sessionStorage.getItem('admin_jwt')`, falls back to `localStorage.getItem('admin_jwt')`
- 401 response: `redirect_after_login` path saved to sessionStorage, then `authService.logout()` called → `window.location.href = '/'`

**Logout:**
```typescript
authService.logout()
  → removes admin_jwt, admin_user, admin_jwt_expiry from sessionStorage AND localStorage
  → window.location.href = '/'   // hard redirect, not React Router navigate
```

**User type expected from Strapi:**
```typescript
{
  id: number,
  username: string,
  email: string,
  role?: { name: string, type?: string }
}
```

The role `type` field must be `'authenticated'` OR `role.name` must be `'admin'` / `'super_admin'` to unlock admin-only routes.

---

## Strapi CMS — CRUD Operations

**Client:** `src/services/strapiClient.ts`

**Base URL:** `import.meta.env.VITE_STRAPI_URL` (baked at build time; set to `https://cms.${DOMAIN_NAME}` in compose)

**Standard request pattern:**
```typescript
strapi.find<T>('orders', {
  sort: ['createdAt:desc'],
  pagination: { limit: 50 },
  filters: { createdAt: { $gte: weekAgo } },
  populate: ['order_items'],
})
// → GET /api/orders?sort[0]=createdAt:desc&pagination[limit]=50&filters[createdAt][$gte]=...&populate[0]=order_items
```

**Methods available on `strapi` client:**

| Method | HTTP | Usage |
|--------|------|-------|
| `find(contentType, params)` | GET | Collection fetch with filters/sort/pagination/populate |
| `findOne(contentType, id)` | GET | Single entry by numeric id |
| `get(url)` | GET | Raw URL (e.g. `/api/ingredients?populate=supplier&pagination[limit]=1000`) |
| `rawGet(url)` | GET | Same as `get` but bypasses Strapi `{ data }` wrapper (for custom controllers) |
| `post(url, body)` | POST | Create or custom action |
| `put(url, body)` | PUT | Update by URL (uses `documentId` for Strapi v5) |
| `delete(url)` | DELETE | Delete by URL |
| `getCortexData(keys)` | GET | Special: fetches `/api/realtime/cortex?keys[]=...` |

**Strapi collections used:**

| Collection | Operations | Component |
|------------|------------|-----------|
| `orders` | find (filters, populate), put (status update) | `DashboardHome`, `KitchenView`, `AnalyticsView`, `NotificationCenter`, `GodMode`, `orders.ts` |
| `ingredients` | find, post (adjust delta) | `DashboardHome`, `StockView`, `NotificationCenter`, `stockService.ts` |
| `customers` | find | `DashboardHome`, `CustomerView` |
| `drivers` | find (is_active filter) | `App.tsx` FleetPlaceholder |
| `platform-settings` | find (by key), put (by id) | `GodMode.tsx` |
| `marketing-campaigns` | find | `AnalyticsView.tsx` |
| `workflow-errors` | find | `NotificationCenter.tsx` |
| `system-config` (singleType) | GET via custom endpoint `/api/control-plane/status` | `ControlPlaneView.tsx` |

**Custom Strapi endpoints:**

| Endpoint | Method | Used by | Notes |
|----------|--------|---------|-------|
| `/api/auth/local` | POST | `authService.login()` | Users-permissions login |
| `/api/users/me?populate=role` | GET | `authService.login()` | Fetch role after login |
| `/api/agent/chat` | POST | `AIChatBubble` | Custom system-config controller; proxies to n8n |
| `/api/control-plane/status` | GET | `ControlPlaneView` | Returns raw JSON (no data wrapper) |
| `/api/realtime/cortex` | GET | `CortexHub` | Returns KITCHEN_LOAD, SURGE_MULTIPLIER, AGENT_STATUS |
| `/api/ingredients/:id/adjust` | POST | `stockService.updateStock()` | Custom atomic delta adjustment |
| `/api/automation/trigger` | POST | `AutomationView` | Proxies to n8n webhook URL |

**Strapi v5 field conventions used throughout codebase:**
- System timestamps use camelCase: `createdAt`, `updatedAt` (NOT `created_at`)
- Stable entry reference uses `documentId` (string), NOT numeric `id` for updates
- Response shape for collections: `{ data: T[], meta: { pagination: {...} } }`
- Response shape for singleType and custom endpoints: raw object (no `data` wrapper) — use `strapi.rawGet()`

---

## AI Agent Chat — n8n Integration

**Flow:**
```
Browser → POST /api/agent/chat (Strapi)
        → Strapi agent-chat.ts controller
        → POST http://n8n-main:5678/webhook/admin/chat (internal Docker network)
        → W_ADMIN_AGENT n8n workflow
             ├── 17 RAG context slices from Strapi DB
             ├── toolHttpRequest to Strapi /api/orders (for order data)
             └── Ollama llama3.1 (ai profile, optional)
        → { reply, actions[], ragSlices[], needsConfirmation, confirmAction }
        → Browser renders reply as Markdown
```

**Request shape from browser:**
```typescript
POST /api/agent/chat
headers: { Authorization: 'Bearer <jwt>', 'Content-Type': 'application/json' }
body: {
  data: {
    message: string,
    sessionId: 'admin-dashboard-session',  // hardcoded, no per-user sessions
    confirm: boolean                         // true when confirming a pending action
  }
}
```

**Feedback request shape:**
```typescript
POST /api/agent/chat
body: {
  data: {
    message: 'feedback',
    sessionId: 'admin-dashboard-session',
    feedbackScore: 1 | -1
  }
}
```

**Client timeout:** 50 seconds (longer than the default 10s for all other Strapi calls).

**Chat history persistence:** `localStorage.getItem('ralphe_agent_history')` — last 50 messages. This is XSS-accessible (unlike the auth JWT in sessionStorage).

**Quick Actions:** 6 preset prompts in `AIChatBubble.tsx` (hardcoded). A TODO comment at line 299 notes these should be fetched dynamically from a Strapi `Inception Prompts` collection in Phase 14.

---

## n8n Workflow Trigger

**Flow:**
```
AutomationView → POST /api/automation/trigger (Strapi)
              → Strapi custom controller proxies POST to webhookUrl
              → Target n8n webhook (e.g. /webhook/resto-bot-main)
```

**Workflows listed (hardcoded in `src/components/AutomationView.tsx`):**

| Workflow ID | n8n Webhook URL | Purpose |
|-------------|-----------------|---------|
| W4 - CORE Bot Agent | `${VITE_N8N_WEBHOOK_BASE}/webhook/resto-bot-main` | Main WhatsApp message router |
| W_INVENTORY_SYNC | `${VITE_N8N_WEBHOOK_BASE}/webhook/sync-inventory` | POS ↔ Strapi inventory sync |
| W_OMNICHANNEL_CONTENT_GEN | `${VITE_N8N_WEBHOOK_BASE}/webhook/generate-content` | LLM marketing asset generation |
| W_KIOSK_ORDER | `${VITE_N8N_WEBHOOK_BASE}/webhook/kiosk-order` | Kiosk order injection |

`VITE_N8N_WEBHOOK_BASE` defaults to `''` if not set — calls would fail silently.

---

## Polling Schedule

The dashboard uses no real-time connection. All freshness is achieved by polling:

| Component | Endpoint(s) | Interval |
|-----------|-------------|----------|
| `DashboardHome` | `orders`, `customers`, `ingredients` (5 parallel) | 30 seconds |
| `KitchenView` / `useOrders` | `orders` | 10 seconds |
| `ControlPlaneView` | `/api/control-plane/status` | 15 seconds |
| `NotificationCenter` | `orders`, `ingredients`, `workflow-errors` | 20 seconds |
| `CortexHub` | `/api/realtime/cortex` | 10 seconds |
| `FleetPlaceholder` | `drivers` | 30 seconds |

**Total polling load at steady state:** ~7 concurrent interval timers, generating 5–8 Strapi API calls every 10 seconds when all views are mounted simultaneously.

---

## Gateway Proxy (nginx)

The admin dashboard's browser calls to Strapi go through the API gateway nginx proxy for admin-specific routes. Relevant nginx config in `project/infra/gateway/nginx.conf`:

```nginx
# Admin Dashboard → Strapi CRUD proxy
location ^~ /v1/portal/ {
  proxy_pass http://cms:1337/api/;
  add_header Access-Control-Allow-Origin "https://admin.srv1258231.hstgr.cloud" always;
}

# Admin-facing n8n webhook proxy
location ^~ /v1/admin/ {
  proxy_pass http://n8n_upstream/webhook/v1/admin/;
}
```

Note: The compose file sets `VITE_STRAPI_URL=https://cms.${DOMAIN_NAME}` which points directly to the CMS subdomain, NOT via `/v1/portal/`. The `/v1/portal/` route exists but is only used if the dashboard is configured to call `${VITE_API_GATEWAY_URL}/v1/portal/`. In production as currently deployed, the dashboard calls `cms.srv1258231.hstgr.cloud` directly — which is on the IP allowlist.

---

## External Service Summary

| Service | How Accessed | Auth | Used For |
|---------|-------------|------|---------|
| Strapi CMS | Direct HTTP (`VITE_STRAPI_URL`) | Users-permissions JWT | All data CRUD, auth, AI agent, control plane |
| n8n | Via Strapi controller only (never direct) | n/a (server-side only) | Workflow triggers, AI agent execution |
| Ollama (llama3.1) | Via n8n workflow only (never direct) | n/a (server-side only) | AI agent LLM responses |
| ui-avatars.com | Direct browser fetch (no auth) | None | User avatar in sidebar |

---

*Integration audit: 2026-03-20*
