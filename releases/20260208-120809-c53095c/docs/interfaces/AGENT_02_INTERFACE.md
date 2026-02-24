# INTERFACE — Agent 2 (Spécialiste Migrations Base de Données)

## Inputs attendus
- Liste des clés templates à seed (CORE_*, WA_ORDER_STATUS_*).
- Besoin de persister préférences (LANG) pour tracking.

## Outputs fournis
- `db/migrations/2026-01-23_p2_epic5_l10n.sql`
- (tests) `tests/fixtures/45_seed_l10n_demo.sql`

## Contrats
- `message_templates(tenant_id,key,locale)` PK.
- `customer_preferences(tenant_id,phone)` PK.
- Fonctions tracking utilisent `normalize_locale`.

## Validation
- Migration idempotente.
- Rollback documenté.
