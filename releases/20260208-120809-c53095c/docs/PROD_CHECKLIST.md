# PROD_CHECKLIST (v3.0)

## Avant mise en prod
- [ ] `.env` rempli (DOMAIN_NAME, SSL_EMAIL, ADMIN_ALLOWED_IPS, TRAEFIK_TRUSTED_IPS, ALLOWED_AUDIO_DOMAINS)
- [ ] secrets présents (`secrets/postgres_password`, `secrets/n8n_encryption_key`, `secrets/traefik_usersfile`)
- [ ] DNS OK pour `console` et `api`
- [ ] `docker compose up -d` sans erreurs
- [ ] Console accessible uniquement depuis IP allowlist + basic auth
- [ ] `GET https://api.<domain>/healthz` retourne 200
- [ ] Webhooks inbound répondent 200 avec token partagé

## Après mise en prod
- [ ] Activer pruning (déjà activé)
- [ ] Sauvegardes Postgres (pg_dump quotidien)
- [ ] Monitoring (Traefik dashboard local, logs)


## Sécurité P0
- [ ] `api_clients` configuré (≥ 1 token par tenant/restaurant)
- [ ] `WEBHOOK_SHARED_TOKEN` supprimé ou gardé uniquement en fallback (temporaire)
- [ ] `ALLOWED_AUDIO_DOMAINS` non vide (sinon STT audio bloqué)

## Fiabilité P0
- [ ] Outbox activée (W8_OPS branche outbox)
- [ ] `outbound_messages` : PENDING/RETRY/SENT/DLQ surveillés

## Backup/Restore P0
- [ ] Backup quotidien (cron) via `./scripts/backup_postgres.sh`
- [ ] Restore drill validé (préprod) via `./scripts/restore_postgres.sh`
