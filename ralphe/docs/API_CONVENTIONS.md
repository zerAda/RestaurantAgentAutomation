# API_CONVENTIONS (v1)

## Domains
- **Console (privé)** : `https://console.<domain>` (n8n UI + admin)
- **API (public)** : `https://api.<domain>`

## Versioning
- Les endpoints publics sont versionnés par path : `/v1/...`
- Les changements non rétro-compatibles créent `/v2/...`

## Auth (inbound)

### Meta Webhooks (WhatsApp / Instagram / Messenger)

**Meta does NOT send custom tokens.** Authentication is via `X-Hub-Signature-256` header:

| Mode | Behavior |
|------|----------|
| `META_SIGNATURE_REQUIRED=off` | Skip validation (dev only) |
| `META_SIGNATURE_REQUIRED=warn` | Validate, log failures, allow through (staging) |
| `META_SIGNATURE_REQUIRED=enforce` | Reject invalid/missing signature (PRODUCTION) |

Meta webhooks use two request types:
- **GET** (webhook verification): Meta sends `hub.mode=subscribe`, `hub.verify_token`, `hub.challenge`
- **POST** (events): Meta sends `X-Hub-Signature-256` header with HMAC-SHA256 signature

When `META_SIGNATURE_REQUIRED=warn|enforce`, valid signature serves as authentication.
Tenant context uses `DEFAULT_TENANT_ID` / `DEFAULT_RESTAURANT_ID` from env.

### Internal API Clients (admin, customer, internal namespaces)

**P0 (prod)**: Token-based auth via `api_clients` table:
- Header: `x-webhook-token: <TOKEN>` (recommended) or `x-api-token: <TOKEN>`
- or `Authorization: Bearer <TOKEN>`
- query param `?token=<TOKEN>`: **disabled by default** (`ALLOW_QUERY_TOKEN=true` for legacy compat only)

Rules:
- Body must **never** provide `tenantId/restaurantId` (ignored if token valid).
- Tokens stored **hashed (sha256)** in DB.
- Invalid attempts logged to `security_events`.

> Legacy fallback: `WEBHOOK_SHARED_TOKEN` supported if `api_clients` table not yet used.


## Contracts (inbound payloads)
Les webhooks inbound utilisent des **contrats JSON Schema versionnés** (voir `schemas/`).

- Header recommandé : `x-contract-version: v2` (sinon v1)
- Fallback body : `contract_version` / `contractVersion`
- Valeurs acceptées : `v1`, `v2`, `1`, `2`
- Payload invalide → HTTP **400** + `security_events.CONTRACT_VALIDATION_FAILED`

⚠️ `tenant_context` dans le payload n'est **jamais** trusted sans preuve (token/API client). Le contexte multi-tenant est résolu côté serveur puis scellé (`tenant_context_seal`).

## Endpoints publics
### Inbound
- POST `/v1/inbound/whatsapp`
- POST `/v1/inbound/instagram`
- POST `/v1/inbound/messenger`

### Health
- GET `/healthz`

## Namespaces réservés (privés)
- `/v1/internal/*` : ops/monitoring/backoffice (allowlist + basic auth au niveau Traefik)
- `/v1/admin/*` : admin/tenants/rbac (allowlist + basic auth)
