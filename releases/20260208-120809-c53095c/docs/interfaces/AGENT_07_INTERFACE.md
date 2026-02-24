# INTERFACE — Agent 7 (Générateur de Templates)

## Inputs
- Liste des clés templates (CORE + tracking).
- Règles renderer safe + allowlist vars.

## Outputs
- Seeds dans `db/migrations/2026-01-23_p2_epic5_l10n.sql`
- Catalogue : `docs/TEMPLATE_CATALOG.md`

## Validation
- Chaque clé a une variante FR et AR (ou fallback documenté).
- Variables listées et cohérentes.
