---
name: ingress_hardening
description: Harden the full ingress chain - Traefik TLS/middlewares, Nginx gateway, and /v1 API contract.
when_to_use:
  - Editing gateway configs (infra/gateway/)
  - Editing Traefik labels in prod compose
  - Adding or modifying /v1 endpoints
  - TLS or routing issues
  - Locking down console/admin/cms
---

# Ingress Hardening (Traefik + Gateway)

## Architecture

```text
Internet -> Traefik (TLS, ACME, middlewares) -> Nginx gateway -> upstreams
```

- Traefik: configured via Docker CLI flags + labels in `docker-compose.hostinger.prod.yml`
- No separate Traefik TOML/YAML — all routing/middleware is in compose labels
- Gateway: `infra/gateway/nginx.conf` + `infra/gateway/proxy_params`

## Traefik requirements

- Only ports 80 (redirect to 443) and 443 publicly exposed
- Dashboard bound to `127.0.0.1:8080` only (never public)
- Trusted IP forwarding explicit (`entryPoints.websecure.forwardedHeaders.trustedIPs`)
- ACME TLS via Let's Encrypt (`certResolver=mytlschallenge`)
- Per-service middlewares via labels:
  - `console.<domain>`: IP allowlist + BasicAuth
  - `admin.<domain>`: IP allowlist + BasicAuth
  - `kiosk.<domain>`: rate limit middleware
  - `api.<domain>`: rate limit + security headers
- Healthchecks and restart policies on all services
- Docker log rotation configured (avoid disk fill)

## Gateway `/v1` contract

- No breaking changes to existing `/v1/*` routes
- Additive only unless deprecation plan exists
- Auth enforced BEFORE upstream proxy call
- Rate limiting per IP
- Request body size limits (`client_max_body_size`)
- Method allowlist per route
- Timeouts: `proxy_connect_timeout`, `proxy_read_timeout`, `proxy_send_timeout`
- Security headers in response
- Token redaction in access logs

## Verification commands

```bash
# TLS check
curl -sI https://api.<domain>/v1/health

# Auth boundary
curl -s -o /dev/null -w "%{http_code}" https://api.<domain>/v1/inbound/wa  # expect 401
curl -s -o /dev/null -w "%{http_code}" -H "x-webhook-token: valid" https://api.<domain>/v1/inbound/wa  # expect 200

# Console protected
curl -s -o /dev/null -w "%{http_code}" https://console.<domain>  # expect 401 or blocked

# Gateway syntax
nginx -t -c infra/gateway/nginx.conf
```

## Deliverables

- Exact diff for compose labels or gateway config
- Updated `scripts/smoke_security_gateway.sh` with new assertions
- Rollback: revert compose/config + `docker compose up -d`
