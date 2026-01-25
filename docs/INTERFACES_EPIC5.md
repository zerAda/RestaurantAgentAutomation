# Interfaces — EPIC5 L10N

## 1) Contract “L10N Context” (W4_CORE)
Champs attendus sur l’event JSON entrant (après parsing inbound) :
```json
{
  "l10n": {
    "enabled": true,
    "hasArabic": true,
    "stickyArEnabled": false,
    "stickyArThreshold": 2
  },
  "state": {
    "localePref": "fr",
    "lastResponseLocale": "fr",
    "arabicScriptCount": 0,
    "stickyAr": false
  }
}
```

**Règles**
- Si `message.type=button` → utiliser `state.lastResponseLocale`.
- `localePref` se modifie uniquement sur `LANG FR|AR`.

## 2) Contract templates
- `templates` : map `{ "KEY::locale": "content" }`
- `templateVars` : map `{ "KEY::locale": ["var1","var2"] }`

## 3) DB schema
### message_templates
PK `(tenant_id,key,locale)`
- `_GLOBAL` = defaults
- tenant override = tenant uuid

### customer_preferences
PK `(tenant_id,phone)`
- alimenté via `LANG`

## 4) Admin WA template commands (W14)
Entrée : message texte `!template ...`
Sortie (parsing) :
- `adminAction`: `TEMPLATE_GET|TEMPLATE_SET|TEMPLATE_VARS|...`
- `adminTemplateKey`, `adminTemplateLocale`, `adminTemplateContent`, `adminTemplateVarsJson`

## 5) Tracking integration
- `build_wa_order_status_payload` cherche `customer_preferences.locale` pour le `user_id`.
- `wa_order_status_text` tente d’abord `message_templates` `_GLOBAL`, puis fallback legacy.
