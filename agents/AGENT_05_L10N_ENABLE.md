# AGENT 05 — Enable L10N by Default (P0-L10N-01)

## Mission
Enable localization features by default for Algeria deployment: Arabic in → Arabic out.

## Priority
**P0 - HIGH** - Core UX requirement for Algeria market.

## Problem Statement
- `.env.example` has `L10N_ENABLED=false` by default
- Production might deploy without enabling L10N
- Arabic-speaking users would get French responses → bad UX
- Violates product requirement: "Arabic in → Arabic out"

## Solution
1. Change default to `L10N_ENABLED=true`
2. Enable `L10N_STICKY_AR_ENABLED=true` (button locale stability)
3. Document the flag and behavior clearly
4. Add smoke tests for AR input/output

## Files Modified
- `config/.env.example`
- `docs/L10N.md` (update documentation)

## Implementation

### .env.example changes
```env
# =========================
# Localization (EPIC5)
# =========================
# Enable script-first locale detection (Arabic script → AR response)
# DEFAULT: true for Algeria deployment
L10N_ENABLED=true

# Sticky AR: once user receives AR response, keep AR for button interactions
# Prevents locale flip when user clicks French-labeled button
L10N_STICKY_AR_ENABLED=true
L10N_STICKY_AR_THRESHOLD=2

# Fallback locale when script cannot be detected
L10N_FALLBACK_LOCALE=fr
```

### Locale Detection Logic (W4_CORE)
```javascript
// Script-first detection
function detectLocale(text) {
  const arabicPattern = /[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]/;
  const hasArabic = arabicPattern.test(text || '');
  
  if (hasArabic) return 'ar';
  return $env.L10N_FALLBACK_LOCALE || 'fr';
}

// Sticky AR logic
function getResponseLocale(inputLocale, state) {
  const stickyEnabled = ($env.L10N_STICKY_AR_ENABLED || 'true').toLowerCase() === 'true';
  const threshold = parseInt($env.L10N_STICKY_AR_THRESHOLD || '2', 10);
  
  if (stickyEnabled && state.lastResponseLocale === 'ar' && state.arResponseCount >= threshold) {
    return 'ar';
  }
  return inputLocale;
}
```

## Rollback
Set `L10N_ENABLED=false` to revert to French-only behavior.

## Tests
```bash
# Test Arabic input → Arabic response
curl -X POST "https://api.example.com/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"msg_id":"test1","from":"123","text":"مرحبا","provider":"wa"}'
# Expected: Response in Arabic

# Test French input → French response  
curl -X POST "https://api.example.com/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"msg_id":"test2","from":"123","text":"Bonjour","provider":"wa"}'
# Expected: Response in French
```

## Validation Checklist
- [ ] Arabic text input returns Arabic response
- [ ] French text input returns French response
- [ ] Mixed input uses Arabic if any Arabic detected
- [ ] Button clicks preserve previous locale (sticky)
- [ ] LANG FR/LANG AR command works
- [ ] Templates exist for both FR and AR
