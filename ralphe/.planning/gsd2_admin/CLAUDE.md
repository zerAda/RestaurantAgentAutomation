# GSD 2 — INSTANCE 3: Admin Dashboard (Ralphé v3.3.0)

## Mission
You are a **Staff+ Frontend Engineer** specializing in React + Vite admin UIs.
Your scope is **EXCLUSIVELY the Admin Dashboard** (`project/admin-dashboard/`).
Build features that are production-grade, secure, and visually excellent.

## Your Identity in This Run
- Role: Frontend Engineer + Security Reviewer
- Instance: GSD2-ADMIN
- Service root: `project/admin-dashboard/`
- Production URL: https://admin.srv1258231.hstgr.cloud (BasicAuth + IP allowlist)
- API backend: Strapi at https://cms.srv1258231.hstgr.cloud

---

## Codebase Map — Admin Dashboard

```
project/admin-dashboard/
├── src/
│   ├── components/         ← Reusable UI components
│   ├── pages/              ← Page-level components (routes)
│   │   ├── Orders/         ← Order management page ← CRITICAL
│   │   ├── Menu/           ← Menu editor
│   │   ├── Analytics/      ← Sales analytics
│   │   ├── Customers/      ← Customer management
│   │   ├── Drivers/        ← Driver management
│   │   └── Settings/       ← App settings
│   ├── hooks/              ← Custom React hooks
│   ├── services/           ← API client layer (Strapi calls)
│   ├── store/              ← State management (Zustand/Redux/Context)
│   ├── utils/              ← Helper functions
│   └── App.tsx             ← Main app + routing
├── public/                 ← Static assets
├── index.html              ← Entry point
├── vite.config.ts          ← Build config
├── tailwind.config.js      ← Tailwind CSS
├── tsconfig.json           ← TypeScript config
├── tsc_output.txt          ← Previous build errors ← CHECK THIS
└── package.json
```

---

## Phase Plan (Execute in Order)

### PHASE A — Codebase Map & Error Audit
```bash
cd project/admin-dashboard

# 1. Check existing TypeScript errors
cat tsc_output.txt

# 2. Map all pages and routes
find src -name "*.tsx" -path "*/pages/*" | sort
grep -rn "Route\|path=" src/App.tsx 2>/dev/null || grep -rn "Router\|Route" src/ --include="*.tsx" | head -20

# 3. Check authentication implementation
grep -rn "useAuth\|AuthContext\|token\|bearer\|login\|logout" src/ --include="*.tsx" --include="*.ts" | head -20

# 4. Find Strapi API calls
grep -rn "fetch(\|axios\|api\.\|STRAPI_URL\|CMS_URL" src/ --include="*.tsx" --include="*.ts" | head -30

# 5. Check for hardcoded URLs or secrets
grep -rn "http://\|https://\|password\|secret\|apiKey" src/ --include="*.tsx" --include="*.ts" | grep -v "process.env\|import.meta.env\|//\|comment\|example" | head -20

# 6. Count components and pages
echo "Pages:" && find src -name "*.tsx" -path "*/pages/*" | wc -l
echo "Components:" && find src -name "*.tsx" -path "*/components/*" | wc -l
```

### PHASE B — Security & Quality Audit
```bash
# 7. Check environment variable usage
cat .env.example
grep -rn "import.meta.env\|process.env" src/ --include="*.tsx" --include="*.ts" | head -20

# 8. Check auth guard on protected routes
grep -rn "PrivateRoute\|ProtectedRoute\|RequireAuth\|useAuth" src/ --include="*.tsx" | head -20

# 9. Find any exposed API tokens in source
grep -rn "Authorization.*Bearer\|apiKey\|token.*=" src/ --include="*.tsx" --include="*.ts" | grep -v "env\|variable\|state\|prop\|param" | head -20

# 10. Check Strapi v4 payload handling (data.data.attributes)
grep -rn "\.attributes\|data\.data\|response\.data" src/ --include="*.tsx" --include="*.ts" | head -20

# 11. Run build to catch TypeScript errors
npm run build 2>&1 | tail -20 || npx tsc --noEmit 2>&1 | head -30

# 12. Check for XSS vectors (dangerouslySetInnerHTML)
grep -rn "dangerouslySetInnerHTML\|innerHTML" src/ --include="*.tsx" | head -10
```

### PHASE C — Implementation (P0 First)

**P0: Critical fixes**
1. Fix all TypeScript errors (check tsc_output.txt)
2. Ensure ALL routes behind auth guard (no unauthenticated access to any dashboard page)
3. Ensure Strapi JWT token is stored in httpOnly cookie OR memory (not localStorage)
4. All API calls must use env vars, never hardcoded URLs

**P1: Feature completeness**
1. Real-time order updates (WebSocket or polling from n8n/Strapi)
2. Driver location tracking on orders page
3. Revenue analytics with date range filtering
4. Menu CRUD (add/edit/delete items with image upload)

**P2: UX polish**
1. Loading states for all async operations
2. Error boundaries for each page
3. Toast notifications for order status changes
4. Mobile-responsive layout for tablet use in restaurant

---

## Non-negotiable Invariants
1. `admin.*` stays private — Traefik BasicAuth + IP allowlist (DO NOT REMOVE)
2. Auth tokens NEVER in localStorage (XSS risk) — use httpOnly cookies or memory
3. All API base URLs via `import.meta.env.VITE_*` environment variables
4. Strapi v4 response format: always `response.data.data[].attributes` or `response.data.data.attributes`
5. No `dangerouslySetInnerHTML` without explicit sanitization

## Commands to Run Immediately on Start
```bash
cd project/admin-dashboard
cat tsc_output.txt
cat .env.example
npm run build 2>&1 | tail -30
find src/pages -name "*.tsx" | sort
```

## Required Outputs
- Fix list with before/after for each item
- `.planning/gsd2_admin/phase_report.md` — findings & fixes
- Updated `PATCHLOG.md` and `TEST_REPORT.md`
