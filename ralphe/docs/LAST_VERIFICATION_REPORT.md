# LAST_VERIFICATION_REPORT (v3.0)

Generated: 2026-01-22 (patch)
## Agent DevSecOps
- ✅ Console privée via Traefik: allowlist + BasicAuth + security headers
- ✅ API publique via Gateway: rate limit + headers
- ✅ Namespaces `/v1/internal` & `/v1/admin` protégés (router priority + allowlist + BasicAuth)

## Agent Architecture
- ✅ Séparation UI (`console`) / API (`api`)
- ✅ n8n non exposé côté API (Traefik → Gateway → n8n)
- ✅ Queue mode (main + worker + redis)

## Agent App / Data
- ✅ Bootstrap DB: `db/bootstrap.sql` (fresh install) + `db/migrations/*` (upgrade idempotent)
- ✅ Aucune interpolation dangereuse trouvée dans les champs SQL `query` (Postgres nodes)

## Agent Workflow QA
- ✅ Webhooks inbound renommés (v1) : whatsapp/instagram/messenger
- ✅ Auth token supporte header / bearer. Query param `?token=...` est **désactivé par défaut** via `ALLOW_QUERY_TOKEN=false`
- ✅ Execute CORE via `CORE_WORKFLOW_ID` env (pas d'ID hardcodé)

## Risques / Notes
- ℹ️ Pour une intégration directe Meta, ajouter une étape de validation signature (`X-Hub-Signature-256`) + GET verify_token.
- ℹ️ Ne jamais activer `ALLOW_QUERY_TOKEN=true` sans besoin legacy (risque de fuite en logs).
- ℹ️ `CORE_WORKFLOW_ID` doit être renseigné après import (script fourni).
