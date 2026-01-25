# INTERFACE — Agent 4 (Expert Intents & NLP Darija)

## Inputs attendus
- Liste des intents cible (P2): `menu`, `checkout`.
- Exemples darija translit attendus.

## Outputs fournis
- `tests/darja_phrases.json` (≥ 50 phrases)
- Mapping dans `W4_CORE` (lists darijaMenu, darijaCheckout)
- Script `scripts/test_darja_intents.py`

## Validation
- ≥50 phrases et taux de match 100% sur les intents minimaux.
