# AGENT_W1_02 — Signature Validator Implementation (CRITICAL)

## Mission
**IMPLÉMENTER** la validation de signature Meta/WhatsApp qui est ABSENTE des workflows.

## Problème Identifié (Audit V2)
```
Impact : spoof / replay possible → spam, commandes fantômes, surcharge DB/outbox.
Preuve : docs/agents parlent de X-Hub-Signature-256... mais aucun workflow W1/W2/W3 
         ne vérifie la signature.
```

## Analyse du Code Actuel

Dans W1_IN_WA.json, le node "B0 - Parse & Canonicalize" ne contient **AUCUNE** validation de signature.

## Solution: Ajouter un Node de Validation

### Code à injecter dans W1/W2/W3 (après Parse, avant Auth)

```javascript
// ============================================
// SIGNATURE VALIDATION NODE
// À ajouter dans W1_IN_WA, W2_IN_IG, W3_IN_MSG
// Position: après "B0 - Parse & Canonicalize", avant "B1 - Auth Check"
// ============================================

const crypto = require('crypto');

// Configuration
const validationMode = ($env.SIGNATURE_VALIDATION_MODE || 'warn').toLowerCase();
const appSecret = ($env.META_APP_SECRET || '').trim();
const timeWindowSec = parseInt($env.SIGNATURE_TIME_WINDOW_SEC || '300', 10);

// Skip if disabled
if (validationMode === 'off' || !appSecret) {
  return [{
    json: {
      ...$json,
      _signature: {
        mode: validationMode,
        skipped: true,
        reason: validationMode === 'off' ? 'disabled' : 'no_app_secret'
      }
    }
  }];
}

// Get signature from headers
const headers = $json.headers || {};
const signature = (
  headers['x-hub-signature-256'] || 
  headers['X-Hub-Signature-256'] || 
  headers['X-HUB-SIGNATURE-256'] ||
  ''
).toString().trim();

// Get raw body for HMAC calculation
const rawBody = $json.rawBody || JSON.stringify($json.body || $json.raw || {});

let signatureValid = false;
let signatureError = null;
let computedSignature = '';

try {
  if (!signature) {
    signatureError = 'missing_signature';
  } else {
    // Compute expected signature
    const hmac = crypto.createHmac('sha256', appSecret);
    hmac.update(rawBody, 'utf8');
    computedSignature = 'sha256=' + hmac.digest('hex');
    
    // Constant-time comparison to prevent timing attacks
    const sigBuffer = Buffer.from(signature);
    const expectedBuffer = Buffer.from(computedSignature);
    
    if (sigBuffer.length === expectedBuffer.length) {
      signatureValid = crypto.timingSafeEqual(sigBuffer, expectedBuffer);
    }
    
    if (!signatureValid) {
      signatureError = 'signature_mismatch';
    }
  }
  
  // Time window check (anti-replay)
  if (signatureValid) {
    const msgTimestamp = $json.body?.timestamp || 
                         $json.body?.entry?.[0]?.time ||
                         $json.raw?.timestamp;
    
    if (msgTimestamp) {
      const msgTime = new Date(msgTimestamp).getTime();
      const now = Date.now();
      const ageSeconds = (now - msgTime) / 1000;
      
      if (ageSeconds > timeWindowSec) {
        signatureValid = false;
        signatureError = 'message_too_old';
      } else if (ageSeconds < -60) {
        // Message from future (clock skew tolerance: 60s)
        signatureValid = false;
        signatureError = 'message_from_future';
      }
    }
  }
  
} catch (err) {
  signatureValid = false;
  signatureError = 'validation_error: ' + (err.message || 'unknown');
}

// Decision based on mode
const shouldBlock = validationMode === 'enforce' && !signatureValid;

// Build result
const result = {
  ...$json,
  _signature: {
    mode: validationMode,
    valid: signatureValid,
    error: signatureError,
    blocked: shouldBlock,
    headerPresent: !!signature
  }
};

// Log to security_events if invalid
if (!signatureValid) {
  result._securityEvent = {
    event_type: 'SIGNATURE_INVALID',
    severity: validationMode === 'enforce' ? 'HIGH' : 'MEDIUM',
    payload: {
      error: signatureError,
      mode: validationMode,
      ip: $json.metadata?.ip || '',
      channel: $json.channel || 'unknown'
    }
  };
}

return [{ json: result }];
```

## Fichiers à Modifier

### 1. workflows/W1_IN_WA.json
- Ajouter node "B0.5 - Signature Validation" après "B0 - Parse & Canonicalize"
- Connecter la sortie à "B1 - Auth Check"
- Si `_signature.blocked === true`, router vers réponse 401

### 2. workflows/W2_IN_IG.json
- Même modification

### 3. workflows/W3_IN_MSG.json
- Même modification

### 4. config/.env.example
```env
# Provider webhook signature validation
# Modes: off (disabled), warn (log only), enforce (reject invalid)
SIGNATURE_VALIDATION_MODE=warn

# Meta App Secret (get from Meta Developer Console)
META_APP_SECRET=

# Time window for replay protection (seconds)
SIGNATURE_TIME_WINDOW_SEC=300
```

## Script d'Application

### apply_signature_validation.sh
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== AGENT_W1_02: Signature Validator ==="

# This agent modifies workflow JSON files
# For safety, we create the code snippet and document the manual steps

PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$0")")")"

# 1. Verify .env has the config
if ! grep -q "SIGNATURE_VALIDATION_MODE" "$PROJECT_ROOT/config/.env.example"; then
    echo "Adding signature config to .env.example..."
    cat >> "$PROJECT_ROOT/config/.env.example" << 'EOF'

# =========================
# SIGNATURE VALIDATION (P0-SEC-03)
# =========================
SIGNATURE_VALIDATION_MODE=warn
META_APP_SECRET=
SIGNATURE_TIME_WINDOW_SEC=300
EOF
    echo "✅ Config added to .env.example"
fi

# 2. Create the signature validation code snippet
mkdir -p "$PROJECT_ROOT/agents/wave1_critical/snippets"
cat > "$PROJECT_ROOT/agents/wave1_critical/snippets/signature_validation_node.js" << 'JSEOF'
// SIGNATURE VALIDATION NODE - Paste into n8n Code node
// Position: After Parse, Before Auth Check

const crypto = require('crypto');

const validationMode = ($env.SIGNATURE_VALIDATION_MODE || 'warn').toLowerCase();
const appSecret = ($env.META_APP_SECRET || '').trim();
const timeWindowSec = parseInt($env.SIGNATURE_TIME_WINDOW_SEC || '300', 10);

if (validationMode === 'off' || !appSecret) {
  return [{json: {...$json, _signature: {mode: validationMode, skipped: true}}}];
}

const headers = $json.headers || {};
const signature = (headers['x-hub-signature-256'] || headers['X-Hub-Signature-256'] || '').trim();
const rawBody = $json.rawBody || JSON.stringify($json.body || $json.raw || {});

let signatureValid = false;
let signatureError = null;

try {
  if (!signature) {
    signatureError = 'missing_signature';
  } else {
    const hmac = crypto.createHmac('sha256', appSecret);
    hmac.update(rawBody, 'utf8');
    const expected = 'sha256=' + hmac.digest('hex');
    
    const sigBuf = Buffer.from(signature);
    const expBuf = Buffer.from(expected);
    signatureValid = sigBuf.length === expBuf.length && crypto.timingSafeEqual(sigBuf, expBuf);
    
    if (!signatureValid) signatureError = 'signature_mismatch';
  }
  
  // Time window check
  if (signatureValid) {
    const ts = $json.body?.timestamp || $json.body?.entry?.[0]?.time;
    if (ts) {
      const age = (Date.now() - new Date(ts).getTime()) / 1000;
      if (age > timeWindowSec) { signatureValid = false; signatureError = 'message_too_old'; }
    }
  }
} catch (e) {
  signatureError = e.message;
}

const blocked = validationMode === 'enforce' && !signatureValid;

return [{json: {
  ...$json,
  _signature: {mode: validationMode, valid: signatureValid, error: signatureError, blocked}
}}];
JSEOF

echo "✅ Signature validation code created at:"
echo "   agents/wave1_critical/snippets/signature_validation_node.js"
echo ""
echo "⚠️  MANUAL STEP REQUIRED:"
echo "   1. Open n8n editor"
echo "   2. Edit W1_IN_WA, W2_IN_IG, W3_IN_MSG"
echo "   3. Add Code node after Parse, before Auth"
echo "   4. Paste the code from signature_validation_node.js"
echo "   5. Connect outputs appropriately"
echo ""
echo "   OR use the JSON patch method (see AGENT_W1_02 docs)"
```

## Vérification Post-Patch

### Test 1: Invalid signature (mode=warn)
```bash
curl -X POST "http://localhost:8080/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Hub-Signature-256: sha256=invalid" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"test","from":"123","text":"test","provider":"wa"}'

# Check security_events for SIGNATURE_INVALID
psql -c "SELECT * FROM security_events WHERE event_type='SIGNATURE_INVALID' ORDER BY created_at DESC LIMIT 1"
```

### Test 2: Valid signature
```bash
PAYLOAD='{"msg_id":"test","from":"123","text":"test","provider":"wa"}'
SIG=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$META_APP_SECRET" | awk '{print $2}')

curl -X POST "http://localhost:8080/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Hub-Signature-256: sha256=$SIG" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"
```

## Rollback
1. Remove the signature validation node from W1/W2/W3
2. Set `SIGNATURE_VALIDATION_MODE=off`

## Critères de Succès
- [ ] Code node présent dans W1/W2/W3
- [ ] Mode warn: logs SIGNATURE_INVALID
- [ ] Mode enforce: rejette signature invalide
- [ ] Signature valide: passe

## Agent Suivant
→ AGENT_W1_03_LEGACY_TOKEN_KILLER
