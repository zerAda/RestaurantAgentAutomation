# AGENT 03 — Provider Signature Validation (P0-SEC-03)

## Mission
Implement webhook signature validation for Meta/WhatsApp providers to prevent spoofing and replay attacks.

## Priority
**P0/P1 - HIGH** - Deploy in warn-only mode first, then enforce.

## Problem Statement
- Webhooks from Meta/WhatsApp include `X-Hub-Signature-256` header
- Currently NOT validated → attacker can spoof/replay webhooks
- No proof of message integrity

## Solution
1. Validate `X-Hub-Signature-256` against payload + app secret
2. Implement time window check (reject old messages)
3. Enforce idempotency (already exists via `msg_id`)
4. Add `SIGNATURE_VALIDATION_MODE` flag: `off`, `warn`, `enforce`

## Files Modified
- `config/.env.example`
- Workflow W1/W2/W3 (signature validation node)
- `db/migrations/2026-01-23_p0_sec03_signature_validation.sql`

## Implementation

### .env.example additions
```env
# Provider webhook signature validation
# Modes: off (disabled), warn (log only), enforce (reject invalid)
SIGNATURE_VALIDATION_MODE=warn

# Meta App Secret (for X-Hub-Signature-256 validation)
META_APP_SECRET=your_meta_app_secret_here

# Signature time window (seconds) - reject messages older than this
SIGNATURE_TIME_WINDOW_SEC=300
```

### Signature Validation Code (for W1/W2/W3)
```javascript
const crypto = require('crypto');

// Get signature from headers
const signature = (headers['x-hub-signature-256'] || headers['X-Hub-Signature-256'] || '').toString();
const appSecret = ($env.META_APP_SECRET || '').trim();
const validationMode = ($env.SIGNATURE_VALIDATION_MODE || 'off').toLowerCase();
const timeWindow = parseInt($env.SIGNATURE_TIME_WINDOW_SEC || '300', 10);

let signatureValid = false;
let signatureError = null;

if (validationMode !== 'off' && appSecret) {
  try {
    // Compute expected signature
    const payload = JSON.stringify(body);
    const expectedSig = 'sha256=' + crypto.createHmac('sha256', appSecret)
      .update(payload)
      .digest('hex');
    
    // Constant-time comparison
    signatureValid = signature && crypto.timingSafeEqual(
      Buffer.from(signature),
      Buffer.from(expectedSig)
    );
    
    // Time window check
    const msgTimestamp = body.timestamp || body.entry?.[0]?.time;
    if (msgTimestamp) {
      const msgTime = new Date(msgTimestamp).getTime();
      const now = Date.now();
      const age = (now - msgTime) / 1000;
      if (age > timeWindow) {
        signatureValid = false;
        signatureError = 'message_too_old';
      }
    }
  } catch (err) {
    signatureError = err.message;
  }
}

// Decision based on mode
const signatureOk = validationMode === 'off' || 
                    validationMode === 'warn' || 
                    signatureValid;

// Log if warn mode and invalid
if (validationMode === 'warn' && !signatureValid) {
  // Log to security_events
  console.warn('Signature validation failed (warn mode):', signatureError);
}

return [{
  json: {
    ...input,
    _signature: {
      mode: validationMode,
      valid: signatureValid,
      error: signatureError,
      enforced: validationMode === 'enforce'
    }
  }
}];
```

## Rollback
Set `SIGNATURE_VALIDATION_MODE=off` in environment.

## Deployment Strategy
1. Deploy with `SIGNATURE_VALIDATION_MODE=warn`
2. Monitor `security_events` for `SIGNATURE_INVALID` entries
3. Verify legitimate traffic passes validation
4. Switch to `SIGNATURE_VALIDATION_MODE=enforce`

## Tests
```bash
# Valid signature (should pass)
PAYLOAD='{"test":"data"}'
SIG=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$META_APP_SECRET" | cut -d' ' -f2)
curl -X POST "https://api.example.com/v1/inbound/whatsapp" \
  -H "X-Hub-Signature-256: sha256=$SIG" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"

# Invalid signature (should fail in enforce mode)
curl -X POST "https://api.example.com/v1/inbound/whatsapp" \
  -H "X-Hub-Signature-256: sha256=invalid" \
  -d '{"test":"data"}'
```

## Validation Checklist
- [ ] Warn mode logs invalid signatures
- [ ] Enforce mode rejects invalid signatures
- [ ] Valid signatures pass through
- [ ] Time window check works
- [ ] security_events contains SIGNATURE_INVALID entries
