// ============================================
// SIGNATURE VALIDATION NODE
// Agent: W1_02 - Signature Validator
// 
// INSTALLATION:
// 1. Add this as a Code node in n8n
// 2. Position: After "B0 - Parse & Canonicalize"
// 3. Before: "B1 - Auth Check" (or equivalent)
// 4. Connect output to existing flow
// 5. Add IF node to check _signature.blocked
// ============================================

const crypto = require('crypto');

// === CONFIGURATION ===
const validationMode = ($env.SIGNATURE_VALIDATION_MODE || 'warn').toLowerCase();
const appSecret = ($env.META_APP_SECRET || '').trim();
const timeWindowSec = parseInt($env.SIGNATURE_TIME_WINDOW_SEC || '300', 10);

// === SKIP IF DISABLED ===
if (validationMode === 'off') {
  return [{
    json: {
      ...$json,
      _signature: {
        mode: 'off',
        skipped: true,
        reason: 'validation_disabled'
      }
    }
  }];
}

if (!appSecret) {
  // No secret configured - cannot validate
  return [{
    json: {
      ...$json,
      _signature: {
        mode: validationMode,
        skipped: true,
        reason: 'no_app_secret_configured',
        warning: 'META_APP_SECRET not set - signature validation skipped'
      }
    }
  }];
}

// === GET HEADERS ===
const headers = $json.headers || $input.first().json.headers || {};
const signature = (
  headers['x-hub-signature-256'] || 
  headers['X-Hub-Signature-256'] || 
  headers['X-HUB-SIGNATURE-256'] ||
  ''
).toString().trim();

// === GET RAW BODY ===
// For HMAC, we need the exact body as received
const rawBody = $json.rawBody || 
                $input.first().json.rawBody ||
                JSON.stringify($json.body || $json.raw || $json);

// === VALIDATION ===
let signatureValid = false;
let signatureError = null;
let computedSignature = '';
let messageAge = null;

try {
  // Step 1: Check signature exists
  if (!signature) {
    signatureError = 'missing_signature_header';
  } else if (!signature.startsWith('sha256=')) {
    signatureError = 'invalid_signature_format';
  } else {
    // Step 2: Compute expected signature
    const hmac = crypto.createHmac('sha256', appSecret);
    hmac.update(rawBody, 'utf8');
    computedSignature = 'sha256=' + hmac.digest('hex');
    
    // Step 3: Constant-time comparison (prevent timing attacks)
    const sigBuffer = Buffer.from(signature);
    const expectedBuffer = Buffer.from(computedSignature);
    
    if (sigBuffer.length !== expectedBuffer.length) {
      signatureValid = false;
      signatureError = 'signature_length_mismatch';
    } else {
      signatureValid = crypto.timingSafeEqual(sigBuffer, expectedBuffer);
      if (!signatureValid) {
        signatureError = 'signature_mismatch';
      }
    }
  }
  
  // Step 4: Time window check (anti-replay protection)
  if (signatureValid) {
    const msgTimestamp = 
      $json.body?.timestamp || 
      $json.body?.entry?.[0]?.time ||
      $json.body?.entry?.[0]?.changes?.[0]?.value?.messages?.[0]?.timestamp ||
      $json.raw?.timestamp ||
      null;
    
    if (msgTimestamp) {
      // Handle both epoch seconds and ISO strings
      let msgTime;
      if (typeof msgTimestamp === 'number') {
        // Epoch seconds (Meta often uses this)
        msgTime = msgTimestamp * 1000;
      } else {
        msgTime = new Date(msgTimestamp).getTime();
      }
      
      const now = Date.now();
      messageAge = Math.round((now - msgTime) / 1000);
      
      if (messageAge > timeWindowSec) {
        signatureValid = false;
        signatureError = `message_too_old_${messageAge}s`;
      } else if (messageAge < -60) {
        // Allow 60s clock skew for messages from "future"
        signatureValid = false;
        signatureError = 'message_from_future';
      }
    }
  }
  
} catch (err) {
  signatureValid = false;
  signatureError = 'validation_exception: ' + (err.message || 'unknown');
}

// === DECISION ===
const shouldBlock = validationMode === 'enforce' && !signatureValid;

// === BUILD RESULT ===
const result = {
  ...$json,
  _signature: {
    mode: validationMode,
    valid: signatureValid,
    error: signatureError,
    blocked: shouldBlock,
    headerPresent: !!signature,
    messageAgeSec: messageAge,
    checkedAt: new Date().toISOString()
  }
};

// === SECURITY EVENT FOR LOGGING ===
if (!signatureValid && signature) {
  // Only log if signature was provided but invalid
  result._signatureSecurityEvent = {
    event_type: 'SIGNATURE_INVALID',
    severity: validationMode === 'enforce' ? 'HIGH' : 'MEDIUM',
    payload_json: JSON.stringify({
      error: signatureError,
      mode: validationMode,
      messageAge: messageAge,
      ip: $json.metadata?.ip || $json._auth?.ip || '',
      channel: $json.channel || 'unknown',
      userId: $json.userId || $json.from || ''
    })
  };
}

return [{ json: result }];
