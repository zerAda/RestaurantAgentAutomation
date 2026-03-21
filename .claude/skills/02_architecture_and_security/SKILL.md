---
name: architecture_and_security
description: Protect system invariants and run threat analysis before changes.
when_to_use:
  - Planning refactors or new features
  - Changing routing, auth, or service topology
  - Security review or audit
  - Before exposing any new endpoint
---

# Architecture Guardian + Threat Analysis

## System invariants (must remain true)

1. `/v1/*` public contract remains stable (backward compatible)
2. n8n is not a public API surface; the gateway is the entrypoint
3. Console is private: BasicAuth + IP allowlist (never exposed by mistake)
4. CMS and Admin Dashboard are private: IP allowlist + optional BasicAuth
5. Inbound endpoints enforce auth before proxying/processing
6. Query-token auth is OFF by default
7. Inbound processing is idempotent (dedupe keys)
8. DB changes are safe + idempotent with backup/restore drills
9. Queue-mode in prod with explicit worker concurrency
10. All images SHA-pinned in CI (supply-chain security)

## STRIDE threat model scope

- Public API: `api.srv1258231.hstgr.cloud/v1/*`
- Private console: `console.srv1258231.hstgr.cloud`
- Private CMS: `cms.srv1258231.hstgr.cloud`
- Private admin: `admin.srv1258231.hstgr.cloud`
- Public kiosk: `kiosk.srv1258231.hstgr.cloud`
- Proxy chain: Traefik -> Nginx gateway -> upstreams
- n8n execution + workflow imports
- Redis queue + Postgres data
- Strapi content API

## Review gate questions (answer explicitly)

- Which invariant could this change weaken?
- How does auth work end-to-end for this change?
- What is the rollback plan?
- What is the minimal proof (smoke test) that it is safe?
- Does this change affect any trust boundary crossing?

## Key files to check

- `project/docker-compose.hostinger.prod.yml` (Traefik labels, middleware chains)
- `project/infra/gateway/nginx.conf` (API routes, auth enforcement)
- `project/.env` (feature flags, auth config)
- `project/secrets/` (credential files)

## Required output

- Invariant impact assessment (pass/fail per invariant)
- STRIDE threat table (if security-relevant change)
- Safer alternative if any invariant is at risk
- Controls evidence map (files/configs proving controls)
