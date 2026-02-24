# AGENT 02 — Disable Legacy Shared Token (P0-SEC-02)

## Mission
Migrate from `WEBHOOK_SHARED_TOKEN` to per-client `api_clients` tokens and disable legacy fallback.

## Priority
**P0 - CRITICAL** - Single shared token = blast radius on compromise.

## Problem Statement
- `WEBHOOK_SHARED_TOKEN` is a single token for ALL clients
- If leaked once → attacker can spoof webhooks for ALL tenants
- No audit trail per client

## Solution
1. Ensure `api_clients` table is seeded with per-tenant tokens
2. Add `LEGACY_SHARED_TOKEN_ENABLED=false` flag
3. Update W1/W2/W3 to reject legacy token when flag is false
4. Add audit logging for token usage

## Files Modified
- `config/.env.example`
- `db/migrations/2026-01-23_p0_disable_legacy_token.sql`
- `tests/fixtures/00_seed_api_clients.sql` (ensure test tokens)

## Implementation

### Migration SQL
```sql
-- Add flag column to track legacy token deprecation
ALTER TABLE api_clients ADD COLUMN IF NOT EXISTS 
  legacy_migrated_at timestamptz NULL;

-- Mark existing clients as migrated
UPDATE api_clients SET legacy_migrated_at = now() 
WHERE legacy_migrated_at IS NULL;
```

### .env.example changes
```env
# DEPRECATED: Legacy shared token - DO NOT USE IN PRODUCTION
# Set to empty string to disable
WEBHOOK_SHARED_TOKEN=

# Legacy token fallback (MUST be false in production)
LEGACY_SHARED_TOKEN_ENABLED=false
```

### Workflow Logic (W1/W2/W3)
```javascript
// In B1 - Auth Check node
const legacyEnabled = ($env.LEGACY_SHARED_TOKEN_ENABLED || 'false').toLowerCase() === 'true';
const shared = ($env.WEBHOOK_SHARED_TOKEN || '').trim();

// Only allow legacy if explicitly enabled AND configured
const legacySharedValid = legacyEnabled && !!shared && (token === shared);

// Log deprecation warning
if (legacySharedValid) {
  console.warn('DEPRECATED: Legacy shared token used. Migrate to api_clients.');
}
```

## Rollback
1. Set `LEGACY_SHARED_TOKEN_ENABLED=true`
2. Ensure `WEBHOOK_SHARED_TOKEN` is configured
3. Redeploy

## Tests
```bash
# Should fail (legacy disabled)
curl -X POST "https://api.example.com/v1/inbound/whatsapp" \
  -H "Authorization: Bearer LEGACY_SHARED_TOKEN" -d '{}'

# Should work (api_clients token)
curl -X POST "https://api.example.com/v1/inbound/whatsapp" \
  -H "Authorization: Bearer CLIENT_SPECIFIC_TOKEN" -d '{}'
```

## Validation Checklist
- [ ] Legacy token rejected when `LEGACY_SHARED_TOKEN_ENABLED=false`
- [ ] Per-client tokens from `api_clients` work
- [ ] security_events logs AUTH_DENY for legacy attempts
- [ ] Deprecation warning logged when legacy used (if enabled)
