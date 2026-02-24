# Rollback — EPIC5 L10N

## Rollback fonctionnel (recommandé)
1) Désactiver la feature:
- Mettre `L10N_ENABLED=false` dans l’environnement (compose / .env)
- Mettre `L10N_STICKY_AR_ENABLED=false` (au cas où)
2) Redémarrer n8n

✅ Effet: retour au comportement legacy, **sans changement DB**.

## Rollback DB (optionnel)
EPIC5 ajoute les objets suivants:
- tables: `message_templates`, `customer_preferences`
- fonctions: `normalize_locale`, patch `wa_order_status_text`, patch `build_wa_order_status_payload`

Si vous devez revenir en arrière côté DB:
- Revenir à un dump avant migration
OU
- Supprimer les objets EPIC5 manuellement (déconseillé en prod car peut casser des appels).

Note:
- garder les tables ne gêne pas si `L10N_ENABLED=false`.
