# GSD SUPER — PROGRESS REPORT
# Ralphé v3.3.0 | Full Stack Audit | 2026-03-20

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 GSD SUPER ► PROGRESS REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Overall: ██████████ 100% — SCAN COMPLETE (7/7 phases)

Phase 1: n8n Workflows        ✅ SCANNED   (92 workflows)
Phase 2: Strapi CMS           ✅ SCANNED   (95 source files)
Phase 3: Admin Dashboard      ✅ SCANNED   (44 components)
Phase 4: Kiosk App            ✅ SCANNED   (20 source files)
Phase 5: Infra & Security     ✅ SCANNED   (nginx, Docker, Traefik)
Phase 6: LLM Optimization     ✅ SCANNED   (Ollama, W_LLM_INTENT, W4_CORE_MENU_GROUNDED)
Phase 7: Interconnections     ✅ SCANNED   (docker-compose, CI/CD)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## RISK REGISTER

### 🔴 P0 — CRITICAL (Fix Immediately)

| # | Component | Finding | Risk | Remediation |
|---|-----------|---------|------|-------------|
| P0-01 | n8n | `W_PAYMENT_CALLBACK.json` has **NO HMAC/signature verification** | Payment fraud, unauthorized callbacks | Add Chargily webhook signature verification before processing |
| P0-02 | Kiosk | `VITE_KIOSK_SECRET` exposed in public JS bundle via `import.meta.env` | Secret leakage on public terminal | Move to server-side proxy; never expose secrets in kiosk bundle |
| P0-03 | Admin | `strapiClient.ts:31` falls back to `localStorage.getItem('admin_jwt')` | XSS token theft survives browser restart | Remove localStorage fallback, use sessionStorage only |
| P0-04 | Infra | Docker Compose has **NO Traefik ipWhiteList or rateLimit** labels | Private services accessible from any IP | Add ipWhiteList middleware for cms.*, admin.*, console.* |

### 🟠 P1 — HIGH (Fix Before Next Deploy)

| # | Component | Finding | Risk | Remediation |
|---|-----------|---------|------|-------------|
| P1-01 | Infra | **Missing Content-Security-Policy** header in nginx.conf | XSS attacks not mitigated by CSP | Add CSP header: `default-src 'self'; script-src 'self'` |
| P1-02 | Strapi | `system-config/routes/agent-chat.ts:10` has `auth: false` | Unauthenticated access to business data context | Add API key or token validation in controller |
| P1-03 | Strapi | `realtime/routes/realtime.ts:12` has `auth: false` | Unauthenticated SSE/realtime access | Add rate limiting and origin check |
| P1-04 | n8n | 46/92 workflows (50%) lack `onError`/`errorWorkflow`/`continueOnFail` | Silent failures, lost orders | Add error branches to remaining 46 workflows |
| P1-05 | Admin | `AIChatBubble.tsx:54` persists chat history to `localStorage` | PII leakage (chat content persists after logout) | Use sessionStorage or encrypt stored chat |

### 🟡 P2 — MEDIUM (Track and Fix)

| # | Component | Finding | Risk | Remediation |
|---|-----------|---------|------|-------------|
| P2-01 | LLM | `W_LLM_INTENT` uses `num_predict: 100` — may be too low for complex intents | Truncated responses on multi-entity orders | Increase to 150-200 for intent classification |
| P2-02 | Admin | 44 components — no lazy loading detected | Slow initial load on admin dashboard | Add React.lazy() for non-critical pages |
| P2-03 | Kiosk | 20 source files — no idle/screensaver detection found | Kiosk shows last customer's cart | Add 60s idle timeout → clear cart → show attract screen |
| P2-04 | Infra | nginx missing `X-XSS-Protection` header | Older browsers lack XSS protection | Add `X-XSS-Protection: 1; mode=block` |

---

## PER-PHASE FINDINGS

### Phase 1: n8n Workflows (92 files)
- ✅ All 92 JSON files are valid syntax
- ✅ No hardcoded passwords in workflow JSON (uses `$env.*` and `$json._strapiConfig.*`)
- ✅ Audio URL validation present with domain allowlist (W4_CORE, W4.1_ROUTER)
- ✅ STT pipeline properly validates audio URLs before fetch
- ⚠️ 46/92 workflows have no error handling
- 🔴 W_PAYMENT_CALLBACK: NO signature verification
- **Top 5 largest workflows**: W14 (107KB), W4_CORE (90KB), W1_IN_WA (67KB), W4.1_ROUTER (61KB), W4_CORE (45KB approx)

### Phase 2: Strapi CMS (95 source files)
- ✅ 95 source files across 30+ content types
- ✅ Populate calls use explicit field lists (not `*`)
- ✅ Agent-chat controller comment explicitly warns about auth
- ⚠️ 2 routes with `auth: false`:
  - `system-config/routes/agent-chat.ts:10` (intentional but risky)
  - `realtime/routes/realtime.ts:12` (intentional, needs rate-limit)
- Content types: menu-item, category, order, customer, delivery-zone, driver, cart, loyalty, creative-asset, ad-campaign, ai-learning, control-plane, and more

### Phase 3: Admin Dashboard (44 files)
- ✅ `authService.ts` uses sessionStorage by design (F-02 fix documented)
- ✅ ErrorBoundary component exists
- ✅ PII redaction utility exists (`utils/pii.ts`)
- ✅ ToastProvider for notifications
- ⚠️ `strapiClient.ts:31` falls back to localStorage (contradicts authService design)
- ⚠️ `AIChatBubble.tsx` stores full chat history in localStorage
- Pages: Dashboard, Orders, Kitchen, Stock, Customers, Marketing, Support, Analytics, Automation, AI Observatory, Growth Agent, God Mode, Control Plane

### Phase 4: Kiosk App (20 files)
- ✅ `strapiClient.ts` explicitly warns: "No VITE_STRAPI_API_TOKEN fallback — kiosk is public terminal"
- ✅ ErrorBoundary component exists
- ✅ VerticalVideoFeed fix from previous session is in place
- 🔴 `strapiClient.ts:76` exposes `VITE_KIOSK_SECRET` via `import.meta.env` in public bundle
- Components: Cart, MenuGrid, VerticalVideoFeed, CustomizerModal, LanguageSelector, AppSwitcher
- Pages: Checkout, FortuneWheel
- Context: CartContext (state management)

### Phase 5: Infrastructure & Security
- ✅ `server_tokens off` — nginx version hidden
- ✅ `X-Content-Type-Options: nosniff`
- ✅ `X-Frame-Options: DENY`
- ✅ `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- ❌ Missing: `Content-Security-Policy` header
- ❌ Missing: `X-XSS-Protection` header
- 🔴 Docker Compose has NO Traefik middleware labels (ipWhiteList, rateLimit, basicAuth) — likely managed at different level or .env

### Phase 6: LLM Optimization
- ✅ W_LLM_INTENT: Ollama at `ollama:11434/api/chat`, model `llama3.1`
- ✅ Temperature: 0.1 (deterministic for intent classification — correct)
- ✅ Config-driven: model, URL, temperature all overridable via `$env` or Strapi config
- ✅ W4_CORE_MENU_GROUNDED: Has AI guardrails and prompt injection protection
- ⚠️ `num_predict: 100` may be insufficient for complex multi-entity orders
- ⚠️ No LLM response caching (Redis) detected

### Phase 7: Project Interconnections
- ✅ 12 CI/CD pipelines in .github/workflows/
- ✅ 70+ scripts in scripts/ directory
- ✅ Makefile with comprehensive targets
- ✅ docker-compose.hostinger.prod.yml defines 12 services
- ⚠️ No Traefik middleware labels found in compose file (may be in .env or separate config)
- 92 n8n workflow JSONs, 95 Strapi source files, 44 admin files, 20 kiosk files
