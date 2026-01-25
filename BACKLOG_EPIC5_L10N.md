# BACKLOG — EPIC 5 (P2) — Localisation FR/AR + Darija (WhatsApp-first)

## Objectif produit
- **Script-first** : si un message entrant contient du **script arabe** → réponse **AR**, sinon **FR**.
- **Darija translit (latin)** : intents minimaux `menu` et `checkout`.
- **Pilotage admin via WhatsApp** : gestion des templates, sans UI web.
- **Zéro régression** si le flag est off.

## Définitions
- **Locale** : `fr` ou `ar`.
- **Script arabe** : détection Unicode `[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]`.
- **Template** : texte transactionnel stocké en DB et résolu par clé + locale.

---

## Stories (ordre conseillé)

### L10N-001 — Réponses FR/AR (script-first) + Darija intents + templates
**En tant que** client, **je veux** recevoir les réponses en arabe quand j’écris en arabe, sinon en français, **afin de** comprendre sans changer de réglage.

**AC**
- (AC-01) Détection script arabe : texte, STT, mixte, chiffres arabes-indic.
- (AC-03) Templates : fallback fr si template ar manquant, rendu safe (variables manquantes → vide, pas de crash).
- (AC-04) Darija latin : ≥ 50 phrases tests, normalisées vers `menu` / `checkout`.
- (AC-05) Boutons WA : cohérence langue (pas de flip sur un click).
- (AC-07) Feature flag `L10N_ENABLED=false` : comportement legacy.

**Livrables**
- Workflow : `workflows/W4_CORE.json` (script-first + renderer + sticky optionnel)
- DB : `db/migrations/2026-01-23_p2_epic5_l10n.sql`
- Docs : `docs/L10N.md`, `docs/EPIC5_ACCEPTANCE_CRITERIA.md`, `docs/ROLLBACK_EPIC5_L10N.md`
- QA : `scripts/test_l10n_script_detection.py`, `scripts/test_darja_intents.py`, `scripts/test_template_render.py`

---

### L10N-002 — Switch langue par user (préférence persistée)
**En tant que** client, **je veux** pouvoir définir une préférence `LANG FR/AR`, **afin de** recevoir des notifications (tracking) dans ma langue.

**AC**
- `LANG FR` / `LANG AR` écrit dans `customer_preferences(tenant_id, phone)`.
- Les notifications tracking utilisent la préférence si elle existe.
- Ne change pas la règle script-first pour les réponses interactives.

**Livrables**
- DB : `customer_preferences` + fonction `build_wa_order_status_payload` patchée.
- Docs : mise à jour `docs/L10N.md`.

---

### L10N-003 — Pilotage admin des templates sur WhatsApp (no UI)
**En tant qu’admin**, **je veux** gérer les templates FR/AR depuis WhatsApp, **afin de** corriger rapidement les messages sans déployer.

**AC**
- Commandes :
  - `!template get <KEY> [fr|ar]`
  - `!template set <KEY> [fr|ar] <CONTENT...>`
  - `!template vars <KEY> [fr|ar] <var1,var2,...>`
- Écritures en **tenant override** (pas `_GLOBAL`).
- RBAC : seuls `admin/owner`.

**Livrables**
- Workflow : `workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json`
- Docs : `docs/L10N_ADMIN_WA_COMMANDS.md`

---

### L10N-004 — Qualité & tests d’intégration
**En tant que** mainteneur, **je veux** une suite de tests + datasets, **afin de** garantir la non-régression.

**AC**
- Integrity Gate passe.
- Jeux de tests : script arabe (≥ 10), renderer (≥ 10), darija (≥ 50).

**Livrables**
- `tests/arabic_script_cases.json`
- `tests/template_render_cases.json`
- `docs/UX_TEST_PLAN_L10N.md`

---

## Risques / Mitigations
- **Flip de langue sur boutons WA** → stocker `state.lastResponseLocale` et le réutiliser.
- **Contenu admin dangereux** (injection variable) → renderer safe + limite taille + pas d’évaluation.
- **Dialects Darija** → matcher minimal + sticky optionnel.

