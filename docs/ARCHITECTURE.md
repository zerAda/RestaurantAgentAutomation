# ARCHITECTURE (v3.0)

## High-level
```
Internet
  |
  |  HTTPS (Let's Encrypt via Traefik)
  v
Traefik (TLS termination, routing, allowlist, basic auth, rate limit)
  |                         |
  | console.<domain>        | api.<domain>
  v                         v
n8n-main (UI, private)     Gateway (Nginx)
                              |
                              v
                           n8n-main (webhooks internal)
                              |
                              v
                         Redis + Worker (queue)
                              |
                              v
                         Postgres (n8n + app schema)
```

## Why this design
- **Stability**: the public API is versioned `/v1/...` and independent from n8n internal paths.
- **Security**: console is private (IP allowlist + BasicAuth). API internal namespaces are private too.
- **Scalability**: queue mode (worker) isolates execution load.
- **Ops**: bootstrap DB single-file, scripts for preflight + smoke.

## Public vs Private
- Public: `api.<domain>/v1/inbound/*` (rate limit + shared token at workflow level)
- Private: `api.<domain>/v1/internal/*` and `/v1/admin/*` (enforced at Traefik: allowlist + BasicAuth)

## Naming conventions
- Domains:
  - `console` = UI/admin
  - `api` = external integrations
- Paths:
  - `/v1/inbound/<channel>` : messages entrants
  - `/v1/internal/<area>/<action>` : ops/backoffice
  - `/v1/admin/<area>/<action>` : admin/tenants/rbac
