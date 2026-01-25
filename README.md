# RESTO BOT – v3.0 (Production-grade)

## Objectif
Pack n8n "high-tech" prêt à déployer sur VPS (Hostinger) avec :
- **UI privée** (console) : `https://console.<domain>`
- **API publique** (gateway) : `https://api.<domain>/v1/...`
- n8n **non exposé** côté API (proxy via gateway)
- stack **queue mode** (n8n main + worker + redis)
- DB bootstrap **single-file** + **migrations idempotentes** (`db/migrations/`)

## Contenu
- `workflows/` : W1..W8
- `db/bootstrap.sql` : schéma + seeds (fresh install)
- `db/migrations/` : patchs idempotents (upgrade in place)
- `infra/gateway/` : config Nginx (API paths stables)
- `docker-compose.hostinger.prod.yml` : stack prod avec Traefik + TLS
- `config/.env.example` : variables requises
- `scripts/` : preflight + workflow-id mapping + smoke tests
- `docs/` : conventions API + runbook + checklist prod

## Quickstart (prod)
1) `cp config/.env.example .env` et renseigne **DOMAIN_NAME**, **SSL_EMAIL**, **ADMIN_ALLOWED_IPS** (+ `TRAEFIK_TRUSTED_IPS`).

   **Note** : `ALLOW_QUERY_TOKEN=false` par défaut (recommandé) pour éviter la fuite de token dans les logs.
2) Crée les secrets dans `./secrets/` (voir `docs/RUNBOOK_HOSTINGER.md`)
3) `docker compose -f docker-compose.hostinger.prod.yml up -d`
4) Ouvre la console : `https://console.<domain>` (BasicAuth + allowlist)
5) Importe `workflows/` et active :
   - W4 CORE
   - W1/W2/W3 inbound
   - W8 OPS
6) Lance `./scripts/generate_workflow_ids.sh` puis exporte `CORE_WORKFLOW_ID`

## API v1 (exemples)
- POST `/v1/inbound/whatsapp`
- POST `/v1/inbound/instagram`
- POST `/v1/inbound/messenger`

Auth : `x-webhook-token: <WEBHOOK_SHARED_TOKEN>` **ou** `Authorization: Bearer <WEBHOOK_SHARED_TOKEN>`

Si tu dois maintenir un ancien client qui ne sait envoyer que `?token=...`, active explicitement `ALLOW_QUERY_TOKEN=true`.

Plus : `docs/API_CONVENTIONS.md`
