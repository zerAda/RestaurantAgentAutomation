# ANTI-FRAUDE — EPIC7 (P1-FRAUD-01)

## Vue d'ensemble

Le système anti-fraude protège contre:
- **Spam/Flood**: Trop de messages en peu de temps
- **Bots**: Payloads suspects
- **No-shows**: Commandes non récupérées
- **Commandes frauduleuses**: Montants élevés, annulations répétées

## Architecture

```
Inbound Message
     │
     ▼
┌─────────────────┐
│ Rate Limit (W1) │ ─── Flood? ──► QUARANTINE
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Bot Detection   │ ─── Suspect? ──► LOG + THROTTLE
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Quarantine Check│ ─── Actif? ──► BLOCK
└────────┬────────┘
         │
         ▼
    Process Normal

Checkout
     │
     ▼
┌─────────────────┐
│ Fraud Eval      │
│ - High total    │
│ - Repeat cancel │
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
 ALLOW    REQUIRE_CONFIRMATION / QUARANTINE
```

## Règles de Fraude

### Règles Inbound (fraud_rules)

| Rule Key | Action | Params |
|----------|--------|--------|
| IN_FLOOD_30S | QUARANTINE | limit_30s=6, quarantine_minutes=10 |
| IN_LONG_TEXT | THROTTLE | max_len=1200 |

### Règles Checkout

| Rule Key | Action | Params |
|----------|--------|--------|
| CO_HIGH_ORDER_TOTAL | REQUIRE_CONFIRMATION | threshold_cents=30000, confirm_ttl_minutes=10 |
| CO_REPEAT_CANCELLED_7D | QUARANTINE | cancel_limit=3, window_days=7, quarantine_minutes=30 |

## Configuration

```env
# Activer/désactiver
FRAUD_INBOUND_ENABLED=true
FRAUD_CHECKOUT_ENABLED=true

# Flood
FRAUD_FLOOD_LIMIT_30S=6
FRAUD_FLOOD_QUARANTINE_MIN=10

# Checkout
FRAUD_HIGH_ORDER_THRESHOLD=3000000  # 30,000 DZD
FRAUD_CANCEL_LIMIT=3
FRAUD_CANCEL_WINDOW_DAYS=7

# Auto-release
QUARANTINE_RELEASE_INTERVAL_SEC=60
```

## Tables

### conversation_quarantine
Quarantaines actives par conversation.

```sql
SELECT * FROM conversation_quarantine
WHERE active = true
  AND expires_at > now();
```

### fraud_rules
Règles configurables.

```sql
-- Modifier un seuil
UPDATE fraud_rules
SET params_json = '{"threshold_cents": 50000}'
WHERE rule_key = 'CO_HIGH_ORDER_TOTAL';

-- Désactiver une règle
UPDATE fraud_rules
SET is_active = false
WHERE rule_key = 'IN_LONG_TEXT';
```

## Fonctions SQL

### apply_quarantine(conversation_key, reason, expires_at, release_policy)
Applique une quarantaine à une conversation.

```sql
SELECT apply_quarantine(
  'wa:+213555123456:resto1',
  'FLOOD_DETECTED',
  now() + interval '10 minutes',
  'AUTO_RELEASE'
);
```

### release_expired_quarantines(limit)
Libère les quarantaines expirées (appelé par W8_OPS).

```sql
SELECT * FROM release_expired_quarantines(50);
```

### fraud_eval_checkout(conversation_key)
Évalue une commande pour fraude.

```sql
SELECT * FROM fraud_eval_checkout('wa:+213555123456:resto1');
-- action: 'REQUIRE_CONFIRMATION'
-- score: 70
-- total_cents: 35000
-- reason: 'HIGH_ORDER_TOTAL'
-- confirm_ttl_minutes: 10
```

### fraud_request_confirmation(conversation_key, total_cents, ttl_minutes)
Génère un code de confirmation pour commande élevée.

```sql
SELECT * FROM fraud_request_confirmation(
  'wa:+213555123456:resto1',
  35000,
  10
);
-- code: '4521'
-- expires_at: '2026-01-23T18:30:00Z'
```

### fraud_confirm(conversation_key, code)
Vérifie le code de confirmation.

```sql
SELECT fraud_confirm('wa:+213555123456:resto1', '4521');
-- true (si valide et non expiré)
```

## Événements de Sécurité

| Event Type | Severity | Description |
|------------|----------|-------------|
| SPAM_DETECTED | MEDIUM | Flood/spam détecté |
| BOT_SUSPECTED | MEDIUM | Comportement de bot |
| QUARANTINE_APPLIED | MEDIUM | Conversation mise en quarantaine |
| QUARANTINE_RELEASED | LOW | Quarantaine levée |
| FRAUD_CONFIRMATION_REQUIRED | MEDIUM | Confirmation demandée |

## Templates WhatsApp

| Key | Usage |
|-----|-------|
| FRAUD_CONFIRM_REQUIRED | Demande de confirmation (code) |
| FRAUD_CONFIRM_INVALID | Code incorrect/expiré |
| FRAUD_THROTTLED | Trop de requêtes |
| FRAUD_QUARANTINED | Accès limité |
| FRAUD_RELEASED | Accès rétabli |

## Intégration Workflow

### W1/W2/W3 (Inbound)
```javascript
// Vérifier quarantaine
const quarantine = await checkQuarantine(conversationKey);
if (quarantine.active) {
  await sendTemplate('FRAUD_QUARANTINED');
  return respond401();
}

// Vérifier flood (rate limit déjà fait au gateway)
const msgCount = await countMessages(conversationKey, 30);
if (msgCount > FRAUD_FLOOD_LIMIT_30S) {
  await applyQuarantine(conversationKey, 'FLOOD', 10);
  await logSecurityEvent('SPAM_DETECTED');
  await sendTemplate('FRAUD_THROTTLED');
  return respond429();
}
```

### W4_CORE (Checkout)
```javascript
// Évaluer fraude
const fraud = await fraudEvalCheckout(conversationKey);

switch (fraud.action) {
  case 'QUARANTINE':
    await applyQuarantine(conversationKey, fraud.reason, fraud.quarantine_minutes);
    await sendTemplate('FRAUD_QUARANTINED');
    break;
    
  case 'REQUIRE_CONFIRMATION':
    const { code, expires_at } = await fraudRequestConfirmation(
      conversationKey, fraud.total_cents, fraud.confirm_ttl_minutes
    );
    await sendTemplate('FRAUD_CONFIRM_REQUIRED', {
      code,
      minutes: fraud.confirm_ttl_minutes
    });
    // Attendre réponse CONFIRM xxxx
    break;
    
  case 'ALLOW':
    // Continuer checkout normal
    break;
}
```

### W8_OPS (Auto-release)
```javascript
// Toutes les 60s
const released = await releaseExpiredQuarantines(50);
for (const q of released) {
  await sendTemplate('FRAUD_RELEASED', {}, q.conversation_key);
  await logSecurityEvent('QUARANTINE_RELEASED', q);
}
```

## Monitoring

### Requêtes utiles

```sql
-- Quarantaines actives
SELECT conversation_key, reason, expires_at
FROM conversation_quarantine
WHERE active = true
ORDER BY expires_at;

-- Top raisons de quarantaine (24h)
SELECT reason, COUNT(*)
FROM conversation_quarantine
WHERE created_at > now() - interval '24 hours'
GROUP BY reason
ORDER BY count DESC;

-- Confirmations en attente
SELECT conversation_key, 
       state_json->'fraud'->>'code' as code,
       state_json->'fraud'->>'expires_at' as expires
FROM conversation_state
WHERE state_json->'fraud'->>'pending' = 'true';

-- Événements fraude (1h)
SELECT event_type, COUNT(*)
FROM security_events
WHERE event_type LIKE 'FRAUD%' OR event_type LIKE 'QUARANTINE%'
  AND created_at > now() - interval '1 hour'
GROUP BY event_type;
```

## Rollback

```env
# Désactiver
FRAUD_INBOUND_ENABLED=false
FRAUD_CHECKOUT_ENABLED=false
```

```sql
-- Libérer toutes les quarantaines
UPDATE conversation_quarantine
SET active = false, released_at = now(), released_reason = 'ADMIN_OVERRIDE';

-- Désactiver règles
UPDATE fraud_rules SET is_active = false;
```
