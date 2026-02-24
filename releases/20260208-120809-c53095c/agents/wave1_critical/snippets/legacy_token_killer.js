// ============================================
// LEGACY TOKEN KILLER
// Agent: W1_03
// 
// INSTALLATION:
// Add this check at the BEGINNING of the auth logic
// in W1_IN_WA, W2_IN_IG, W3_IN_MSG workflows
// (in the B1 - Auth Check node or equivalent)
// ============================================

// === LEGACY TOKEN KILL-SWITCH ===
const legacyKillSwitch = ($env.LEGACY_SHARED_TOKEN_ENABLED || 'false').toLowerCase();
const legacyEnabled = legacyKillSwitch === 'true';

// Get the shared token config
const sharedToken = ($env.WEBHOOK_SHARED_TOKEN || '').trim();
const sharedTokenConfigured = !!sharedToken;

// Get the token from the request (already extracted in previous node)
const token = $json._auth?.token || $json.token || '';

// Check if this is an attempt to use the legacy shared token
const isLegacyTokenAttempt = sharedTokenConfigured && token && token === sharedToken;

// If legacy is disabled but someone is trying to use it
if (!legacyEnabled && isLegacyTokenAttempt) {
  // BLOCK the request
  return [{
    json: {
      ...$json,
      _auth: {
        ...$json._auth,
        authOk: false,
        scopeOk: false,
        legacyBlocked: true,
        reason: 'legacy_shared_token_disabled',
        message: 'Legacy shared token authentication is disabled. Use api_clients tokens.'
      },
      _securityEvent: {
        event_type: 'LEGACY_TOKEN_BLOCKED',
        severity: 'HIGH',
        payload_json: JSON.stringify({
          ip: $json.metadata?.ip || '',
          channel: $json.channel || 'unknown',
          user_agent: $json.metadata?.userAgent || '',
          timestamp: new Date().toISOString()
        })
      }
    }
  }];
}

// If legacy IS enabled and this is a valid legacy token (backward compat during migration)
if (legacyEnabled && isLegacyTokenAttempt) {
  // Log deprecation warning
  console.warn('DEPRECATED: Legacy shared token used. Migrate to api_clients.');
  
  return [{
    json: {
      ...$json,
      _auth: {
        ...$json._auth,
        authOk: true,
        scopeOk: true,  // Legacy token has all scopes
        authMode: 'legacy_shared',
        legacyWarning: 'This authentication method is deprecated. Migrate to api_clients.'
      },
      _securityEvent: {
        event_type: 'LEGACY_TOKEN_USED',
        severity: 'MEDIUM',
        payload_json: JSON.stringify({
          ip: $json.metadata?.ip || '',
          channel: $json.channel || 'unknown',
          message: 'Legacy token still in use - migration pending'
        })
      }
    }
  }];
}

// Not a legacy token attempt - continue with normal auth flow
// (Pass through to existing api_clients authentication)
return [$json];
