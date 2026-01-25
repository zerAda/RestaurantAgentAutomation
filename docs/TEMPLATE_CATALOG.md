# Catalogue Templates — FR/AR (EPIC5)

## Conventions
- `key` = identifiant fonctionnel stable (ex: `CORE_CLARIFY`).
- `locale` = `fr` | `ar`.
- Résolution : tenant override → `_GLOBAL` → fallback texte.
- Variables : placeholders `{{var}}`.
- Sécurité : seules les variables “allowlistées” via `message_templates.variables` sont rendues ; sinon remplacées par vide.

---

## CORE

### `CORE_CLARIFY`
- **FR** (GLOBAL) : “Je n’ai pas bien compris. Tu peux préciser ? ...”
- **AR** (GLOBAL) : “لم أفهم جيداً. هل يمكنك التوضيح؟ ...”
- Variables : *(aucune)*

### `CORE_MENU_HEADER`
- FR : “📋 Menu ...”
- AR : “📋 القائمة ...”
- Variables : *(aucune)*

### `CORE_LANG_SET_FR`
- FR : confirmation `LANG FR`
- Variables : *(aucune)*

### `CORE_LANG_SET_AR`
- AR : confirmation `LANG AR`
- Variables : *(aucune)*

---

## Tracking WhatsApp (EPIC3)
> Ces clés sont utilisées par la fonction SQL `wa_order_status_text`.

Variables possibles :
- `order_id` (obligatoire)
- `eta` (optionnel, string pré-formaté avec `\nETA: ...`)

### `WA_ORDER_STATUS_CONFIRMED`
- Variables : `order_id`, `eta`

### `WA_ORDER_STATUS_PREPARING`
- Variables : `order_id`, `eta`

### `WA_ORDER_STATUS_READY`
- Variables : `order_id`, `eta`

### `WA_ORDER_STATUS_OUT_FOR_DELIVERY`
- Variables : `order_id`, `eta`

### `WA_ORDER_STATUS_DELIVERED`
- Variables : `order_id`

### `WA_ORDER_STATUS_CANCELLED`
- Variables : `order_id`

---

## Exemples “override tenant”
### Exemple FR — plus court
`!template set CORE_CLARIFY fr Je n’ai pas compris. Tu peux reformuler ?`

### Exemple AR — plus simple
`!template set CORE_CLARIFY ar لم أفهم. هل يمكن أن تعيد؟`

### Exemple tracking AR — tone plus dial.
`!template set WA_ORDER_STATUS_READY ar 📦 طلبك واجد (#{{order_id}}).{{eta}}`

### Mise à jour variables
`!template vars WA_ORDER_STATUS_READY ar order_id,eta`
