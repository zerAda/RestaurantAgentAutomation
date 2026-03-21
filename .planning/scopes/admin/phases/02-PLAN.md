---
phase: 02-security-hardening
plan: 02
type: execute
wave: 2
depends_on: [01]
files_modified:
  - project/admin-dashboard/src/App.tsx
  - project/admin-dashboard/src/components/AIChatBubble.tsx
  - project/admin-dashboard/src/pages/ControlPlaneView.tsx
autonomous: true
requirements: [S-01, S-02, S-03, S-04]

must_haves:
  truths:
    - "A Strapi user with role type='authenticated' and role name='staff' cannot access /analytics or /control-plane"
    - "Only users with role name='admin' or role name='super_admin' see admin-only nav items and routes"
    - "AI chat history is cleared on tab close (sessionStorage, not localStorage)"
    - "AIChatBubble does not read admin_jwt directly from storage — it calls authService.getToken()"
    - "Portainer dead anchor link is removed from ControlPlaneView"
  artifacts:
    - path: "project/admin-dashboard/src/App.tsx"
      provides: "Corrected RBAC gate"
      contains: "role?.name?.toLowerCase() === 'admin'"
    - path: "project/admin-dashboard/src/components/AIChatBubble.tsx"
      provides: "authService.getToken() usage, sessionStorage chat history"
      contains: "authService.getToken()"
    - path: "project/admin-dashboard/src/pages/ControlPlaneView.tsx"
      provides: "Portainer link removed or env-gated"
  key_links:
    - from: "project/admin-dashboard/src/App.tsx isFullAdmin"
      to: "Strapi user role.name field"
      via: "role.name check only — role.type check removed"
      pattern: "role\\.name"
    - from: "project/admin-dashboard/src/components/AIChatBubble.tsx"
      to: "project/admin-dashboard/src/services/authService.ts"
      via: "authService.getToken() import"
      pattern: "authService\\.getToken"
---

<objective>
Harden the three security issues identified in the codebase audit: the RBAC gate that grants all authenticated Strapi users full admin access (S-02), the AI chat history stored in XSS-accessible localStorage (S-01), and the AIChatBubble component that bypasses authService and reads the JWT key directly from storage (S-03). Also remove the dead Portainer anchor link (S-04).

Purpose: Right now, any user who can log in to the admin dashboard gets full access to all admin routes including `/control-plane`, `/analytics`, and `/ai-observatory`. This is the highest-impact security fix after the runtime bugs are resolved.

Output: Three modified source files. No new dependencies. No API changes. Role distinction is enforced at both the nav rendering level and the route rendering level in App.tsx.
</objective>

<execution_context>
All work is inside `project/admin-dashboard/src/`.
Build command: `cd project/admin-dashboard && npm run build`
Type-check command: `cd project/admin-dashboard && npx tsc --noEmit`
</execution_context>

<context>
<interfaces>

From project/admin-dashboard/src/services/authService.ts (getToken export):
```typescript
export const authService = {
    // ...
    getToken: (): string | null => {
        return store.getItem(TOKEN_KEY);  // store = sessionStorage
    },
    getUser: (): { id: number; username: string; email: string; role?: { name: string; type?: string } } | null => {
        // ...
    },
    // ...
};
```

From project/admin-dashboard/src/App.tsx (current broken RBAC gate, lines 60-62):
```typescript
const user = authService.getUser();
const isAdminRole = user?.role?.type === 'authenticated'   // BUG: matches ALL Strapi users
  || user?.role?.name?.toLowerCase() === 'admin'
  || user?.role?.name?.toLowerCase() === 'super_admin';
const isFullAdmin = isAdminRole;
```

From project/admin-dashboard/src/components/AIChatBubble.tsx (current broken token reads, lines 115 and 177):
```typescript
// Line 115 (sendMessage):
const token = sessionStorage.getItem('admin_jwt') || localStorage.getItem('admin_jwt');

// Line 177 (sendFeedback):
const token = sessionStorage.getItem('admin_jwt') || localStorage.getItem('admin_jwt');
```

From project/admin-dashboard/src/components/AIChatBubble.tsx (current storage, lines 44-55):
```typescript
const STORAGE_KEY = 'ralphe_agent_history';
function loadHistory(): ChatMessage[] {
    try {
        const raw = localStorage.getItem(STORAGE_KEY);   // BUG: localStorage = XSS-accessible
        // ...
    }
}
function saveHistory(messages: ChatMessage[]) {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(messages.slice(-50))); }  // BUG
    // ...
}
```

From project/admin-dashboard/src/pages/ControlPlaneView.tsx (dead link, line 135 approximately):
```html
<a href="#">Open Orchestrator</a>
```

Note on Strapi role structure:
- Every user created via users-permissions has role.type = 'authenticated' (this is the default type name for the role group, NOT a meaningful distinction between users)
- role.name is what distinguishes users: 'Authenticated', 'admin', 'super_admin', 'staff', etc.
- The fix: remove the `role.type === 'authenticated'` check entirely; keep only `role.name` checks
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Fix RBAC gate in App.tsx (S-02)</name>
  <files>
    project/admin-dashboard/src/App.tsx
  </files>
  <behavior>
    - Test 1: isFullAdmin is false when role.type='authenticated' and role.name='Authenticated' (default Strapi user)
    - Test 2: isFullAdmin is false when role.type='authenticated' and role.name='staff'
    - Test 3: isFullAdmin is true when role.name='admin'
    - Test 4: isFullAdmin is true when role.name='super_admin'
    - Test 5: isFullAdmin is true when role.name='Admin' (case-insensitive check)
  </behavior>
  <action>
Fix S-02 in `project/admin-dashboard/src/App.tsx`.

Locate lines 60-62 (the current RBAC gate):
```typescript
const isAdminRole = user?.role?.type === 'authenticated'
  || user?.role?.name?.toLowerCase() === 'admin'
  || user?.role?.name?.toLowerCase() === 'super_admin';
```

Replace with (remove the `role.type` check entirely — it matches ALL users):
```typescript
const isFullAdmin =
    user?.role?.name?.toLowerCase() === 'admin'
    || user?.role?.name?.toLowerCase() === 'super_admin';
```

Also remove the now-redundant intermediate `isAdminRole` variable and the `const isFullAdmin = isAdminRole;` line — write it directly as `const isFullAdmin = ...`.

Create `src/App.test.ts` to verify RBAC logic in isolation:
```typescript
import { describe, it, expect } from 'vitest';

// Extracted from App.tsx for testability
function computeIsFullAdmin(role?: { name?: string; type?: string }): boolean {
    return (
        role?.name?.toLowerCase() === 'admin'
        || role?.name?.toLowerCase() === 'super_admin'
    );
}

describe('RBAC gate', () => {
    it('denies default Strapi authenticated user', () => {
        expect(computeIsFullAdmin({ type: 'authenticated', name: 'Authenticated' })).toBe(false);
    });
    it('denies staff role', () => {
        expect(computeIsFullAdmin({ type: 'authenticated', name: 'staff' })).toBe(false);
    });
    it('grants admin role', () => {
        expect(computeIsFullAdmin({ name: 'admin' })).toBe(true);
    });
    it('grants super_admin role', () => {
        expect(computeIsFullAdmin({ name: 'super_admin' })).toBe(true);
    });
    it('is case-insensitive', () => {
        expect(computeIsFullAdmin({ name: 'Admin' })).toBe(true);
        expect(computeIsFullAdmin({ name: 'SUPER_ADMIN' })).toBe(true);
    });
});
```

IMPORTANT: The `isFullAdmin` variable is used in two places in App.tsx:
1. In the nav items rendering (`{isFullAdmin && <NavItem .../>}`)
2. In the Routes block (`{isFullAdmin && <><Route.../></>}`)

Both usages must continue to work — do not rename the variable or change how it is used downstream.

After the fix, a user with `role.type='authenticated'` and `role.name='Authenticated'` (the Strapi default) will NOT see admin nav items and will be redirected to `/dashboard` if they navigate directly to `/analytics`. This is the intended behavior.
  </action>
  <verify>
    <automated>cd "project/admin-dashboard" && npx tsc --noEmit && npm test -- --run --reporter=verbose 2>&1 | grep -E "(PASS|FAIL|RBAC)"</automated>
  </verify>
  <done>
    - `tsc --noEmit` exits 0
    - All 5 RBAC gate tests pass
    - `App.tsx` line with `role.type === 'authenticated'` is removed
    - `App.tsx` contains `isFullAdmin` using only `role.name` checks
  </done>
</task>

<task type="auto">
  <name>Task 2: Move chat history to sessionStorage and fix direct JWT reads (S-01, S-03)</name>
  <files>
    project/admin-dashboard/src/components/AIChatBubble.tsx,
    project/admin-dashboard/src/pages/ControlPlaneView.tsx
  </files>
  <action>
Fix S-01 (chat history in localStorage) and S-03 (direct JWT storage reads) in `AIChatBubble.tsx`.
Fix S-04 (dead Portainer link) in `ControlPlaneView.tsx`.

--- AIChatBubble.tsx changes ---

1. Add authService import at the top of the file (after existing imports):
```typescript
import { authService } from '../services/authService';
```

2. Fix chat history storage (S-01):

Find `loadHistory()` function (around line 45):
```typescript
function loadHistory(): ChatMessage[] {
    try {
        const raw = localStorage.getItem(STORAGE_KEY);
```
Change `localStorage` to `sessionStorage`:
```typescript
function loadHistory(): ChatMessage[] {
    try {
        const raw = sessionStorage.getItem(STORAGE_KEY);
```

Find `saveHistory()` function (around line 53):
```typescript
function saveHistory(messages: ChatMessage[]) {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(messages.slice(-50))); }
```
Change to:
```typescript
function saveHistory(messages: ChatMessage[]) {
    try { sessionStorage.setItem(STORAGE_KEY, JSON.stringify(messages.slice(-50))); }
```

3. Fix `clearHistory()` function (around line 168):
```typescript
const clearHistory = () => {
    localStorage.removeItem(STORAGE_KEY);
```
Change to:
```typescript
const clearHistory = () => {
    sessionStorage.removeItem(STORAGE_KEY);
```

4. Fix S-03 — direct JWT reads in `sendMessage` (around line 115):
```typescript
const token = sessionStorage.getItem('admin_jwt') || localStorage.getItem('admin_jwt');
```
Change to:
```typescript
const token = authService.getToken();
```

5. Fix S-03 — direct JWT read in `sendFeedback` (around line 177):
```typescript
const token = sessionStorage.getItem('admin_jwt') || localStorage.getItem('admin_jwt');
```
Change to:
```typescript
const token = authService.getToken();
```

Note: Both `sendMessage` and `sendFeedback` also read `VITE_STRAPI_URL` from `import.meta.env`. Leave that unchanged — it is correct.

--- ControlPlaneView.tsx change ---

Fix S-04 — dead Portainer anchor. Find the anchor:
```html
<a href="#">Open Orchestrator</a>
```

Replace with an env-gated link. If `VITE_PORTAINER_URL` is set, render a real link; otherwise render nothing (do not show a broken link):
```typescript
{import.meta.env.VITE_PORTAINER_URL && (
    <a
        href={import.meta.env.VITE_PORTAINER_URL}
        target="_blank"
        rel="noopener noreferrer"
        className="..."
    >
        Open Orchestrator
    </a>
)}
```
Keep the same Tailwind classes the original anchor had. If you cannot find the original classes in context, use `className="text-xs text-zinc-400 hover:text-white underline transition-colors"`.

Important: Do NOT add `VITE_PORTAINER_URL` to the production `.env` file — it would expose the Portainer URL without IP allowlisting. The env-gate ensures the link only appears if the operator has explicitly configured it.
  </action>
  <verify>
    <automated>cd "project/admin-dashboard" && npx tsc --noEmit && grep -n "localStorage.getItem.*admin_jwt\|localStorage.setItem.*agent_history\|localStorage.getItem.*agent_history" src/components/AIChatBubble.tsx</automated>
  </verify>
  <done>
    - `tsc --noEmit` exits 0
    - The grep command returns no matches (all localStorage accesses for JWT and chat history are gone from AIChatBubble.tsx)
    - `AIChatBubble.tsx` contains `authService.getToken()` in both sendMessage and sendFeedback
    - `AIChatBubble.tsx` contains `sessionStorage` for STORAGE_KEY operations
    - `ControlPlaneView.tsx` dead `href="#"` anchor is replaced with env-gated conditional
  </done>
</task>

</tasks>

<verification>
After both tasks:

1. TypeScript: `cd project/admin-dashboard && npx tsc --noEmit` — exits 0.

2. Tests: `cd project/admin-dashboard && npm test -- --run` — all tests pass including the new RBAC gate suite.

3. Build: `cd project/admin-dashboard && npm run build` — exits 0.

4. RBAC manual verification (grep-based):
   - `grep -n "role?.type" project/admin-dashboard/src/App.tsx` — must return no matches (the type check is fully removed)
   - `grep -n "isFullAdmin" project/admin-dashboard/src/App.tsx` — must show uses in nav and Routes sections

5. Storage verification (grep-based):
   - `grep -n "localStorage" project/admin-dashboard/src/components/AIChatBubble.tsx` — must return no matches (all localStorage references removed)
   - `grep -n "authService.getToken" project/admin-dashboard/src/components/AIChatBubble.tsx` — must show 2 matches (sendMessage and sendFeedback)

6. Portainer verification:
   - `grep -n "href=\"#\"" project/admin-dashboard/src/pages/ControlPlaneView.tsx` — must return no matches
</verification>

<success_criteria>
- `npm run build` succeeds
- `npm test -- --run` passes all tests including 5 RBAC gate assertions
- A user with `role.name='Authenticated'` (default Strapi role) is treated as non-admin — admin routes render nothing (React Router falls through to the `/dashboard` redirect)
- `AIChatBubble.tsx` has zero direct `localStorage` reads/writes for JWT or chat history
- `ControlPlaneView.tsx` has no dead `href="#"` link
</success_criteria>

<rollback>
All changes are isolated TypeScript edits to 3 files. No new dependencies, no migrations, no infrastructure changes.

If the RBAC change locks out an existing admin user: check their Strapi `role.name` in the database. If it is `'Authenticated'` (default), update it to `'admin'` via Strapi admin panel or SQL:
```sql
-- Check current role names
SELECT u.email, r.name FROM up_users u
JOIN up_users_role_lnk lnk ON lnk.user_id = u.id
JOIN up_roles r ON r.id = lnk.role_id;
```
If the role name is wrong, update in Strapi admin panel: Users & Permissions > Roles > assign the user to 'admin'.

Individual file revert: `git checkout -- project/admin-dashboard/src/App.tsx`
</rollback>

<output>
After completion, create `.planning/scopes/admin/phases/02-SUMMARY.md` with:
- Files modified
- Security issues fixed (S-01, S-02, S-03, S-04)
- RBAC gate change description (what was the old condition, what is the new condition)
- Test results
- Strapi role names that grant admin access (for ops reference)
</output>
