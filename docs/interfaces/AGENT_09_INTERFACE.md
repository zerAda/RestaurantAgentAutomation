# INTERFACE — Agent 9 (Ingénieur QA Automatisation)

## Inputs
- Workflows `W4_CORE` et `W14`.
- Datasets tests.

## Outputs
- Scripts tests :
  - `scripts/test_l10n_script_detection.py`
  - `scripts/test_template_render.py`
  - `scripts/test_darja_intents.py`
- Validation via `scripts/integrity_gate.sh`.

## Validation
- Tous les scripts sortent 0.
- Integrity gate passe.
