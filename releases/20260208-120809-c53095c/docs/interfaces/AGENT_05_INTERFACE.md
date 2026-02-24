# INTERFACE — Agent 5 (Développeur API Multilingue)

## Scope EPIC5
EPIC5 est principalement **workflow + DB**. Cet agent garantit que :
- les payloads inbound normalisés incluent le champ `l10n` si nécessaire,
- les fonctions tracking utilisent une locale stable (préférence DB),
- aucun endpoint admin/customer n’est affecté.

## Inputs
- Gateway `/v1/inbound/*` et mapping vers n8n.
- Outbox/tracking (EPIC3) : fonction `build_wa_order_status_payload`.

## Outputs
- Revue de compatibilité (incluse dans `docs/L10N_ARCHITECTURE.md`).

## Validation
- `scripts/test_harness.sh` passe.
