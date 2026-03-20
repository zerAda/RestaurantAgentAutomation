# Coding Conventions

**Analysis Date:** 2026-03-16

## Naming Patterns

**Files:**
- React components: PascalCase, e.g., `AIChatBubble.tsx`, `KitchenDisplay.tsx`
- Services/utilities: camelCase, e.g., `authService.ts`, `strapiClient.ts`
- Strapi API files: camelCase with hyphens for multi-word slugs, e.g., `admin-audit-log`, `agent-sessions`
- Test files: `setup.test.ts` (co-located with source)
- TypeScript files: `.ts` extension; React components use `.tsx`

**Functions:**
- camelCase for all function names
- Prefix network/async handlers with descriptive verbs: `fetchData()`, `loadHistory()`, `handleReset()`
- Event handlers: `handle<Event>` pattern, e.g., `handleReset`, `handleSend`, `handleLogout`
- Utility functions: standalone, e.g., `formatTime()`, `cn()`, `buildQueryString()`
- Hooks: `use<Feature>` pattern, e.g., `useOrders()`, `useUpdateOrderStatus()`, `useCallback()`

**Variables:**
- camelCase for all variables and state
- Constants: UPPERCASE_SNAKE_CASE, e.g., `TOKEN_KEY`, `STRAPI_URL`, `QUICK_ACTIONS`
- State hooks: descriptive names, e.g., `[isLoading, setIsLoading]`, `[messages, setMessages]`
- Refs: suffix with `Ref`, e.g., `messagesEndRef`, `inputRef`, `frameRef`
- Type prefixes: `_token` for module-level private vars, e.g., `let _token: string | null = null`

**Types:**
- Interface names: PascalCase, e.g., `ChatMessage`, `StrapiResponse<T>`, `FindParams`, `AgentSession`
- Type aliases: PascalCase, e.g., `OrderStatus`
- Props interfaces: `<ComponentName>Props`, e.g., `Props { children, fallback }`
- Generic parameters: Single capital letter or descriptive, e.g., `<T>`, `<StrapiOrder>`
- Enums: UPPERCASE values for multi-word options, e.g., `'DELIVERY' | 'TAKEOUT' | 'DINE_IN'`

## Code Style

**Formatting:**
- No linter config file present; projects rely on default TypeScript/ESLint settings
- ESLint uses flat config (`eslint.config.js`)
- Target: ES2022 for TypeScript compilation
- JSX: React 19 with automatic JSX transform

**Linting:**
- Tool: ESLint 9.x with TypeScript plugin
- Config location: `eslint.config.js` (both admin-dashboard and kiosk-app)
- Extends: `@eslint/js`, `typescript-eslint`, `eslint-plugin-react-hooks`, `eslint-plugin-react-refresh`
- Rules applied: React hooks enforcement, React refresh plugin rules
- No enforced trailing commas, semicolons optional by practice
- IDE: Integrated TypeScript strict mode enforcement (see tsconfig)

**TypeScript Configuration:**
- Target: ES2022, bundler module resolution
- Strict mode enabled: `strict: true`
- Check flags: `noUnusedLocals`, `noUnusedParameters`, `noFallthroughCasesInSwitch`, `noUncheckedSideEffectImports`
- Module detection: `force` (ESNext modules required)
- JSX: `react-jsx` (no manual React import needed)
- Path aliases: `@/*` maps to `./src/*`
- No emit on TypeScript errors: `noEmit: true` (build breaks on type errors)

## Import Organization

**Order:**
1. External/third-party imports (React, libraries)
2. Internal service/utility imports (services, hooks)
3. Component imports (from same or parent directories)
4. Type-only imports (if any)

**Path Aliases:**
- `@/*` used in frontend projects to reference `src/` directory
- Example: `import { cn } from "@/lib/utils"`
- Reduces relative path noise in component trees

**Examples:**
```typescript
// Good: External → Internal services → Local utilities
import { useState, useEffect, useRef } from 'react';
import { strapi } from '../services/strapiClient';
import { cn } from '@/lib/utils';
import { ErrorBoundary } from './ErrorBoundary';
```

## Error Handling

**Patterns:**
- Try-catch for async operations: `try { await fetch(...) } catch (error) { console.error(...) }`
- Null-coalescing: `return user ? JSON.parse(user) : null`
- Graceful fallbacks: `catch { /* fall back to basic user from login response */ }`
- Event dispatch for network errors: `window.dispatchEvent(new CustomEvent('strapi-network-error', { detail: { message } }))`
- Auth errors: 401 triggers logout + redirect, 403 treated as permission error (no logout)
- API error parsing: Extract Strapi error message from JSON response before throwing
- Timeout handling: AbortController with configurable timeouts (default 10s, up to 60s for long-running ops)

**Custom Errors:**
```typescript
// Strapi error extraction
let errorMessage = `Strapi ${res.status}: ${res.statusText}`;
try {
  const errorBody = await res.json();
  const strapiMsg = errorBody?.error?.message;
  if (strapiMsg) errorMessage = strapiMsg;
} catch { /* fall back to HTTP status */ }
throw new Error(errorMessage);
```

**Error Boundaries:**
- Class-based `ErrorBoundary` component in `src/components/ErrorBoundary.tsx`
- Wraps entire app to catch render errors
- Displays user-friendly French error messages
- Fallback UI includes error details in monospace font
- Reset action: clears hash or reloads page

## Logging

**Framework:** Console (no structured logging library)

**Patterns:**
- Use `console.error()` for failures: `console.error('[ComponentName] Failed to update:', err)`
- Square brackets for component/module scope: `[AuthService]`, `[KitchenView]`, `[Strapi]`
- Log on critical failures (auth, network, state update failures)
- Avoid logging sensitive data (tokens, passwords, user IDs beyond first 12 chars)
- Network errors emit CustomEvents instead of logging directly

**Examples:**
```typescript
console.error('[AuthService] Login failed — is Strapi reachable?');
console.error('[KitchenView] Failed to update order status:', err);
window.dispatchEvent(new CustomEvent('strapi-auth-error', { detail: { code: 401 } }));
```

## Comments

**When to Comment:**
- Explain WHY, not WHAT (code already shows what)
- Document non-obvious fixes or workarounds with issue references: `// F-02 FIX: Use sessionStorage instead of localStorage`
- Explain business logic divergences: `// Users-Permissions API returns { jwt: '...', user: { ... } }`
- Document field mappings and transformations: `// Strapi field is 'total_amount' in DA (not 'total_cents' in centimes)`
- Add section headers for large functions: `/* ── Types ── */`, `/* ── Quick Action Presets ── */`

**Comment Style:**
- Single-line: `// Comment about this line`
- Multi-line sections: `/* ── Section Name ── */` with hyphens for visual clarity
- Block comments for major logic blocks
- Inline comments for surprising behavior or workarounds

**JSDoc/TSDoc:**
- Not consistently used; types inferred from TypeScript signatures
- Function parameters and return types clearly typed in interfaces
- No formal JSDoc blocks; rely on IDE type hints
- Example: `export function cn(...inputs: ClassValue[])` — signature is self-documenting

## Function Design

**Size:**
- Most functions 20-60 lines
- Custom hooks typically 30-50 lines with state setup
- Utility functions under 10 lines preferred (e.g., `cn()`, `formatTime()`)
- Components kept under 100 lines when possible (split into smaller components otherwise)

**Parameters:**
- Use destructuring for multiple params: `{ value, duration = 600, prefix = '', ... }`
- Provide sensible defaults in destructured params
- Avoid positional arguments for optional params

**Return Values:**
- Explicit return types on all functions: `(): Promise<boolean>`, `(): StrapiResponse<T>`
- Generic types for API responses: `request<T>(path: string): Promise<T>`
- React components return JSX (implicit)
- Boolean returns for success/failure checks: `login()` returns `boolean`

**Example:**
```typescript
export const authService = {
  login: async (email: string, password: string): Promise<boolean> => {
    try {
      const res = await fetch(`${STRAPI_URL}/api/auth/local`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ identifier: email, password }),
      });
      if (!res.ok) return false;
      // ... process response
      return true;
    } catch {
      console.error('[AuthService] Login failed');
      return false;
    }
  },
};
```

## Module Design

**Exports:**
- Named exports for utilities, services, components: `export function cn()`, `export const strapi = { ... }`
- Default exports for React components: `export default function KitchenDisplay()`
- Barrel files (index.ts) used minimally
- Services exported as objects with methods: `export const strapi = { get, find, post, ... }`

**Service Patterns:**
- Services are objects with method chains: `strapi.find<T>(contentType, params)` returns promise
- Request configuration passed as `RequestOptions extends RequestInit` with `timeoutMs` custom field
- Token management centralized: `getToken()`, `setToken()`, stored in sessionStorage

**Example Service:**
```typescript
export const strapi = {
  get: <T>(path: string) => request<StrapiResponse<T>>(path),
  find: <T>(contentType: string, params?: FindParams) =>
    request<StrapiResponse<T[]>>(`/api/${contentType}${buildQueryString(params)}`),
  post: <T>(path: string, data: unknown) =>
    request<StrapiResponse<T>>(path, { method: 'POST', body: JSON.stringify({ data }) }),
};
```

## Security Practices

**Token Storage:**
- Use `sessionStorage` (tab-isolated, cleared on close) NOT `localStorage`
- Clear localStorage fallback keys on logout for migration from old code
- Token sent via `Authorization: Bearer <token>` header, never query params

**Data Handling:**
- Truncate user IDs in display: `user.slice(0, 12)` to avoid exposing full ID
- Parse Strapi error JSON before throwing to show real validation messages
- Never log auth tokens or sensitive fields

## Production vs Local Differences

**URLs:**
- Production: `import.meta.env.VITE_STRAPI_URL || 'https://cms.' + domain`
- Local dev: Falls back to `cms.localhost` if env not set
- Never hardcode URLs; always use env variables with fallbacks

**Token Lifespan:**
- 24-hour session expiry enforced via timestamp in sessionStorage
- After expiry, `isAuthenticated()` forces logout automatically

---

*Convention analysis: 2026-03-16*
