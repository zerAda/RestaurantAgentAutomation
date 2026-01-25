# EPIC 5 — Localisation (FR/AR Darija) — Critères d'acceptation

## AC-01 — Détection script arabe (script-first)
- Quand le message entrant contient au moins un caractère arabe (Unicode Arabic blocks), la réponse sortante utilise `locale = ar`.
- Quand le message ne contient pas d'écriture arabe, la réponse sortante utilise `locale = fr`.
- Le comportement doit fonctionner sur:
  - messages texte,
  - messages STT (transcription),
  - messages mixtes (latin + arabe),
  - chiffres arabes-indic (ex: ١٢٣).

## AC-02 — Commande de choix de langue (préférence utilisateur)
- `LANG FR` enregistre la préférence `fr` pour le couple `(tenant_id, phone)`.
- `LANG AR` enregistre la préférence `ar` pour le couple `(tenant_id, phone)`.
- La préférence est persistée **uniquement** via la commande `LANG ...` (pas d'écriture DB sur simple détection de script).

## AC-03 — Fallback templates (zéro crash)
- Si un template manque pour une clé/locale, le système:
  1) cherche la variante `_GLOBAL`,
  2) sinon renvoie un message de fallback lisible.
- Les variables d'un template sont validées (les variables manquantes ne doivent pas faire échouer le workflow).

## AC-04 — Darija (latin) intents minimalistes
- Les expressions Darija en latin sont interprétées au minimum pour:
  - `menu` (afficher la carte),
  - `checkout` (valider / finaliser).
- Les tests doivent inclure au moins 50 phrases.

## AC-05 — Boutons WhatsApp: cohérence de langue
- Les actions via boutons (`message.type=button`) ne doivent pas faire basculer la langue de réponse.
- La langue utilisée est celle de la dernière réponse (`state.lastResponseLocale`) quand disponible.

## AC-06 — Admin WhatsApp (pilotage)
- Les admins/owners peuvent gérer les templates via la console WhatsApp (workflow `W14_ADMIN_WA_SUPPORT_CONSOLE`).
- Commandes supportées:
  - `!template get <KEY> [fr|ar]`
  - `!template set <KEY> [fr|ar] <CONTENT...>`
  - `!template vars <KEY> [fr|ar] <var1,var2,...>`

## AC-07 — Feature flags
- Le système peut être désactivé via `L10N_ENABLED=false` sans régression.

## AC-08 — Qualité
- `scripts/integrity_gate.sh` passe.
- Les workflows JSON restent valides (jq).

