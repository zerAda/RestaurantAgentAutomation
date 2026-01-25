# INTERFACE — Agent 1 (Architecte Système Localisation)

## Inputs attendus
- Règles produit EPIC5 (script-first, darija, admin WA).
- Contraintes n8n : workflow `W4_CORE` et console admin `W14`.
- Schéma DB disponible (Agent 2) ou hypothèse : `message_templates`, `customer_preferences`.

## Outputs fournis
- `docs/L10N_ARCHITECTURE.md`
- `docs/DECISIONS_L10N.md`

## Contrats / décisions clés
- `responseLocale` déterminé par script arabe.
- Boutons WA stabilisés via `state.lastResponseLocale`.

## Validation
- Docs cohérentes avec flags `.env.example`.
- Aucune “dette doc” (pas de flags non existants).
