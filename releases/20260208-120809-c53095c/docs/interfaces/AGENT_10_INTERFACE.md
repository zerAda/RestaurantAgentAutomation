# INTERFACE — Agent 10 (DevOps Feature Flags)

## Inputs
- Flags nécessaires EPIC5.

## Outputs
- `.env.example` contient : `L10N_ENABLED`, `L10N_STICKY_AR_*`.
- `docs/RELEASE_PLAN_EPIC5.md`.

## Validation
- Aucun flag documenté sans impl.
- Default : `L10N_ENABLED=false` (no regression).
