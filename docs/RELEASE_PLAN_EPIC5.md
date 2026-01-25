# EPIC 5 — Plan de release (L10N FR/AR + Darija)

## Pré-requis
- DB accessible (Postgres) + accès `psql`.
- Workflows n8n importés (au minimum `W4_CORE` et `W14_ADMIN_WA_SUPPORT_CONSOLE`).
- Outbox/Tracking EPIC3 déjà en place (pour notifications).

## Variables d’environnement
Dans `.env` / docker-compose :
- `L10N_ENABLED=true`
- (optionnel) `L10N_STICKY_AR_ENABLED=true`
- (optionnel) `L10N_STICKY_AR_THRESHOLD=2`

> Recommandation : activer `L10N_ENABLED=true` d’abord, puis activer sticky après validation terrain.

## Étapes de déploiement
1. **Appliquer migration DB**
   - `db/migrations/2026-01-23_p2_epic5_l10n.sql`
   - Vérifier : tables `message_templates`, `customer_preferences` + fonctions `wa_order_status_text` et `build_wa_order_status_payload`.

2. **Importer / mettre à jour workflows**
   - Importer `workflows/W4_CORE.json`
   - Importer `workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json`

3. **Activer les flags**
   - Définir `L10N_ENABLED=true` dans l’environnement n8n.
   - Redémarrer n8n (ou reload env) si nécessaire.

4. **Smoke tests (manuel)**
   - Client en FR : `menu` → réponse FR.
   - Client en AR : `القائمة` → réponse AR.
   - Mixed : `salut من فضلك` → réponse AR.
   - Bouton : après réponse AR, cliquer un bouton → réponse reste AR.
   - `LANG AR` → confirmation AR + préférence persistée.

5. **Pilotage admin WhatsApp**
   - `!template get CORE_CLARIFY ar`
   - `!template set CORE_CLARIFY ar ...`

## Rollback
- Couper `L10N_ENABLED=false` (retour comportement legacy immédiat).
- Si rollback DB nécessaire : voir `docs/ROLLBACK_EPIC5_L10N.md`.

## Observabilité minimale
- Surveiller : erreurs workflow `W4_CORE` + erreurs DB.
- Vérifier qu’aucun message ne “flip” de langue sur boutons.

