# INTERFACE — Agent 3 (Ingénieur Backend Localisation)

## Inputs attendus
- Contrat JSON inbound normalisé (W1/W2/W3).
- Accès aux templates chargés DB (maps `templates`, `templateVars`).

## Outputs fournis
- `workflows/W4_CORE.json` (script-first, darija, buttons stable, renderer safe)
- `scripts/test_l10n_script_detection.py`

## Conventions
- `state.lastResponseLocale` set sur chaque réponse utile.
- Pas de crash si template manquant.

## Validation
- Scénarios `docs/UX_TEST_PLAN_L10N.md` passent.
- `scripts/integrity_gate.sh` passe.
