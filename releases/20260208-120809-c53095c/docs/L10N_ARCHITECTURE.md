# Architecture — EPIC5 Localisation (FR/AR + Darija)

## Vue d’ensemble
La localisation est implémentée **au niveau du workflow CORE** (n8n), avec :
- Détection du **script arabe** (Unicode) sur les messages entrants.
- Règle **script-first** pour déterminer `responseLocale`.
- Templates FR/AR chargés depuis la DB (`message_templates`) et rendus via un **renderer safe**.
- Préférence utilisateur persistée via `LANG FR|AR` dans `customer_preferences` (utile pour les notifications tracking).
- Console admin WhatsApp (W14) pour gérer les templates sans UI.

---

## Flux (runtime)
### 1) Inbound
`W1_IN_WA` reçoit le webhook WhatsApp, normalise payload, auth, idempotence, puis exécute `W4_CORE`.

### 2) Pre-processing L10N (W4_CORE)
Node “context” :
- `hasArabic = /[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]/.test(text)`
- `detectedLocale = hasArabic ? 'ar' : 'fr'`
- `localePref` chargé depuis : `state.localePref` → `customer_preferences` (si jointure) → fallback `fr`.

### 3) Règle de réponse
Node “intent/router” :
- `responseLocale = hasArabic ? 'ar' : 'fr'`
- Exception boutons WA : `message.type=button` → garder `state.lastResponseLocale` si présent.
- (Optionnel) sticky AR : si `state.stickyAr=true` et darija translit match → `responseLocale='ar'`.

### 4) Templates
- Les templates sont chargés (lookup DB) et passés à `T(key, vars, locale, fallback)`.
- Renderer safe :
  - remplace `{{var}}` si dans allowlist `message_templates.variables`
  - supprime placeholders restants
  - jamais d’évaluation / code exec.

### 5) Persistance d’état
- `state.localePref` est mis à jour **seulement** via `LANG FR|AR`.
- `state.lastResponseLocale` sert à stabiliser la langue sur les boutons.

---

## Schéma DB
### message_templates
Clé primaire : `(tenant_id, key, locale)`
- `_GLOBAL` = defaults.
- Overrides tenant = `tenant_id=<uuid tenant>`.

### customer_preferences
Clé primaire : `(tenant_id, phone)`
- Stocke la locale choisie via `LANG`.

---

## Admin WhatsApp (W14)
- Parse : `!template get|set|vars ...`
- RBAC : admin/owner uniquement.
- Writes : uniquement overrides tenant.

---

## Points de vigilance
- **RTL** en AR : privilégier des textes courts, éviter mise en forme lourde.
- **Boutons** : toujours fournir un titre FR/AR via helper `BTN()`.
- **No regression** : `L10N_ENABLED=false` → on conserve la logique legacy.
