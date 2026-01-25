# PAYMENTS — Paiements Algérie (P1-PAY-01)

## Vue d'ensemble

Le système de paiement supporte:
- **COD (Cash on Delivery)**: Paiement à la livraison
- **DEPOSIT_COD**: Acompte + reste en COD
- **CIB/Edahabia**: (Préparé, non activé)

## Flux de Paiement

### 1. COD Simple (commandes < seuil)
```
Client commande → Commande confirmée → Livraison → Paiement COD → Terminé
```

### 2. COD avec Acompte (commandes >= seuil)
```
Client commande → Demande acompte envoyée → Client paie acompte → Commande confirmée → Livraison → Paiement COD reste → Terminé
```

### 3. Client Bloqué (soft blacklist)
```
Client commande → Refus ou demande prépaiement total
```

## Configuration

### Variables d'environnement

```env
# Activer les méthodes
PAYMENT_COD_ENABLED=true
PAYMENT_DEPOSIT_ENABLED=true
PAYMENT_CIB_ENABLED=false      # Future
PAYMENT_EDAHABIA_ENABLED=false # Future

# Acompte
PAYMENT_DEPOSIT_MODE=PERCENTAGE  # ou FIXED
PAYMENT_DEPOSIT_PERCENTAGE=30    # 30% d'acompte
PAYMENT_DEPOSIT_THRESHOLD=300000 # 3000 DZD min pour exiger acompte

# Limites COD
PAYMENT_COD_MAX_AMOUNT=1000000   # 10,000 DZD max

# Confiance (exemption acompte)
PAYMENT_TRUST_MIN_ORDERS=3       # 3 commandes réussies
PAYMENT_TRUST_MIN_SCORE=70       # Score >= 70

# Timeout
PAYMENT_DEPOSIT_TIMEOUT_MIN=30   # 30 min pour payer l'acompte
```

### Configuration par Restaurant (DB)

```sql
INSERT INTO restaurant_payment_config (
  restaurant_id,
  cod_enabled, deposit_enabled,
  deposit_mode, deposit_percentage, deposit_threshold,
  no_deposit_min_orders, no_deposit_min_score
) VALUES (
  '00000000-0000-0000-0000-000000000001',
  true, true,
  'PERCENTAGE', 30, 300000,
  3, 70
);
```

## Tables

### payment_intents
Intention de paiement pour chaque commande.

| Colonne | Type | Description |
|---------|------|-------------|
| intent_id | UUID | Identifiant unique |
| order_id | BIGINT | Commande liée |
| method | ENUM | COD, DEPOSIT_COD, CIB, ... |
| status | ENUM | PENDING, DEPOSIT_PAID, CONFIRMED, ... |
| total_amount | INT | Montant total (centimes) |
| deposit_amount | INT | Acompte requis |
| deposit_paid | INT | Acompte payé |
| cod_amount | INT | Montant COD |

### customer_payment_profiles
Profil de confiance client.

| Colonne | Type | Description |
|---------|------|-------------|
| user_id | TEXT | ID utilisateur |
| total_orders | INT | Commandes totales |
| completed_orders | INT | Commandes réussies |
| no_show_count | INT | No-shows |
| trust_score | INT | Score 0-100 |
| requires_deposit | BOOL | Force acompte |
| soft_blacklisted | BOOL | Bloqué temporairement |

## Fonctions SQL

### calculate_deposit(restaurant_id, user_id, total_amount)
Calcule si un acompte est requis et son montant.

```sql
SELECT * FROM calculate_deposit(
  '00000000-0000-0000-0000-000000000001',
  '+213555123456',
  500000  -- 5000 DZD
);
-- deposit_required: true
-- deposit_amount: 150000  -- 1500 DZD (30%)
-- reason: 'standard_deposit'
```

### create_payment_intent(...)
Crée une intention de paiement pour une commande.

```sql
SELECT * FROM create_payment_intent(
  tenant_id, restaurant_id, order_id,
  conversation_key, user_id, total_amount,
  'COD'
);
```

### confirm_deposit_payment(intent_id, amount)
Confirme la réception d'un acompte.

```sql
SELECT confirm_deposit_payment(
  '550e8400-e29b-41d4-a716-446655440000',
  150000
);
```

### collect_cod_payment(intent_id, amount, actor)
Enregistre la collecte du COD à la livraison.

```sql
SELECT collect_cod_payment(
  '550e8400-e29b-41d4-a716-446655440000',
  350000,
  'driver'
);
```

## Templates WhatsApp

| Key | Usage |
|-----|-------|
| PAYMENT_DEPOSIT_REQUIRED | Demande d'acompte |
| PAYMENT_DEPOSIT_CONFIRMED | Acompte reçu |
| PAYMENT_COD_INFO | Info paiement livraison |
| PAYMENT_EXPIRED | Timeout paiement |
| PAYMENT_BLOCKED | Client bloqué |

## Intégration Workflow (W4_CORE)

### Au checkout
```javascript
// 1. Évaluer fraude
const fraudResult = await fraud_eval_checkout(conversationKey);

if (fraudResult.action === 'QUARANTINE') {
  // Bloquer
  await sendTemplate('FRAUD_QUARANTINED');
  return;
}

if (fraudResult.action === 'REQUIRE_CONFIRMATION') {
  // Demander confirmation (code)
  await fraud_request_confirmation(conversationKey, total, ttl);
  await sendTemplate('FRAUD_CONFIRM_REQUIRED', { code, minutes });
  return;
}

// 2. Créer intention de paiement
const payment = await create_payment_intent(...);

if (payment.deposit_required) {
  // Envoyer demande acompte
  await sendTemplate('PAYMENT_DEPOSIT_REQUIRED', {
    amount: payment.deposit_amount / 100,
    minutes: 30
  });
} else {
  // COD direct
  await sendTemplate('PAYMENT_COD_INFO', {
    amount: payment.cod_amount / 100
  });
}
```

## Anti-fraude Intégré

Le système de paiement s'intègre avec EPIC7:

1. **Score de confiance**: Calculé après chaque commande
2. **Acompte automatique**: Pour nouveaux clients ou commandes élevées
3. **Blacklist soft**: Après 2+ no-shows (30 jours)
4. **Prépaiement forcé**: Pour clients blacklistés

## Rollback

```sql
-- Désactiver les fonctionnalités
UPDATE restaurant_payment_config SET deposit_enabled = false;

-- Ou rollback complet (voir migration)
```

## Future: CIB/Edahabia

Structure prête pour intégration:
- `payment_intents.external_ref`: Référence transaction
- `payment_intents.external_provider`: 'CIB' ou 'EDAHABIA'
- `restaurant_payment_config.cib_merchant_id`: ID marchand

Workflow d'intégration:
1. Générer lien de paiement CIB/Edahabia
2. Envoyer au client via WhatsApp
3. Webhook callback pour confirmer paiement
4. Mettre à jour `payment_intents`
