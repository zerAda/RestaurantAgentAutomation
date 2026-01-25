# INTERFACE — Agent 8 (Curateur de Données Test)

## Inputs
- Règle detection script arabe.
- Renderer safe et allowlist.

## Outputs
- `tests/arabic_script_cases.json`
- `tests/template_render_cases.json`
- `tests/fixtures/45_seed_l10n_demo.sql`

## Validation
- JSON valides (`python -m json.tool ...`).
- Couverture des cas limites (digits arabes-indic, mix, empty).
