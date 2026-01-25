# API_CONVENTIONS (v1)

## Domains
- **Console (privé)** : `https://console.<domain>` (n8n UI + admin)
- **API (public)** : `https://api.<domain>`

## Versioning
- Les endpoints publics sont versionnés par path : `/v1/...`
- Les changements non rétro-compatibles créent `/v2/...`

## Auth (inbound)
**P0 (prod)** : auth multi-tenant par token **par client** (table `api_clients`) :
- Header : `x-webhook-token: <TOKEN>` (recommandé) ou `x-api-token: <TOKEN>`
- ou `Authorization: Bearer <TOKEN>`
- query param `?token=<TOKEN>` : **désactivé par défaut** (activer via `ALLOW_QUERY_TOKEN=true` uniquement pour compat legacy)

Règles :
- Le body ne doit **jamais** fournir `tenantId/restaurantId` (ignorés si token valide).
- Les tokens sont stockés **hashés (sha256)** en DB.
- Les tentatives invalides sont journalisées dans `security_events`.

> Fallback legacy (compat) : `WEBHOOK_SHARED_TOKEN` reste supporté si la table `api_clients` n’est pas encore utilisée.


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
