# AGENT_W1_03 — Legacy Token Killer (CRITICAL)

## Mission
**DÉSACTIVER RÉELLEMENT** le WEBHOOK_SHARED_TOKEN legacy qui représente un blast radius énorme.

## Problème Identifié (Audit V3)
```
Impact : 1 secret compromis = blast radius énorme (multi-tenant) + bypass inbound.
Preuve : W1 calcule legacySharedValid et peut basculer en authMode='legacy_shared'.
```

## Analyse du Code Actuel

Dans W1_IN_WA.json, node "B0 - Parse & Canonicalize" :
```javascript
const shared = ($env.WEBHOOK_SHARED_TOKEN || '').toString().trim();
const legacySharedConfigured = !!shared;
const legacySharedValid = !!token && legacySharedConfigured && (token === shared);
```

Et dans "B1 - Auth Check" :
```javascript
// Le legacy token EST encore accepté si configuré
```

## Solution Multi-Étapes

### Étape 1: Vérifier migration api_clients

Avant de tuer le legacy, s'assurer que tous les clients sont migrés vers `api_clients`.

```sql
-- Vérifier les clients actifs
SELECT client_id, name, tenant_id, scopes, active, created_at 
FROM api_clients 
WHERE active = true;

-- Compter les clients
SELECT COUNT(*) as active_clients FROM api_clients WHERE active = true;
```

### Étape 2: Ajouter kill-switch dans .env

```env
# DEPRECATED: Legacy shared token - DO NOT USE IN PRODUCTION
# Leave EMPTY to disable (recommended)
WEBHOOK_SHARED_TOKEN=

# Explicit kill-switch (defense in depth)
LEGACY_SHARED_TOKEN_ENABLED=false
```

### Étape 3: Modifier le code d'auth dans W1/W2/W3

Le code actuel accepte le legacy token. Il faut ajouter un check explicite.

```javascript
// Dans B1 - Auth Check, AJOUTER au début:

const legacyKillSwitch = ($env.LEGACY_SHARED_TOKEN_ENABLED || 'false').toLowerCase();
const legacyEnabled = legacyKillSwitch === 'true';

// Modifier la logique existante:
const legacySharedValid = legacyEnabled && 
                          !!token && 
                          legacySharedConfigured && 
                          (token === shared);

// Log si tentative legacy
if (!legacyEnabled && legacySharedConfigured && token === shared) {
  // Tentative d'utilisation du legacy token alors qu'il est désactivé
  console.warn('BLOCKED: Legacy shared token attempt while disabled');
  // Ajouter à security_events
}
```

### Étape 4: Script d'application

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== AGENT_W1_03: Legacy Token Killer ==="

PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$0")")")"
ENV_FILE="$PROJECT_ROOT/config/.env.example"
ENV_PATCHED="$PROJECT_ROOT/config/.env.example.patched"

# 1. Vérifier que .env.patched existe et contient le kill-switch
if grep -q "LEGACY_SHARED_TOKEN_ENABLED=false" "$ENV_PATCHED" 2>/dev/null; then
    echo "✅ Kill-switch présent dans .env.example.patched"
else
    echo "⚠️  Ajout du kill-switch à .env.example.patched"
    echo "" >> "$ENV_PATCHED"
    echo "# Legacy Token Kill-Switch (AGENT_W1_03)" >> "$ENV_PATCHED"
    echo "LEGACY_SHARED_TOKEN_ENABLED=false" >> "$ENV_PATCHED"
    echo "WEBHOOK_SHARED_TOKEN=" >> "$ENV_PATCHED"
fi

# 2. Vérifier le .env.example actuel
if grep -q "LEGACY_SHARED_TOKEN_ENABLED" "$ENV_FILE"; then
    echo "✅ Kill-switch présent dans .env.example"
else
    echo "⚠️  Ajout du kill-switch à .env.example"
    echo "" >> "$ENV_FILE"
    echo "# Legacy Token Kill-Switch (AGENT_W1_03)" >> "$ENV_FILE"
    echo "LEGACY_SHARED_TOKEN_ENABLED=false" >> "$ENV_FILE"
fi

# 3. Créer snippet de code pour W1/W2/W3
mkdir -p "$PROJECT_ROOT/agents/wave1_critical/snippets"

cat > "$PROJECT_ROOT/agents/wave1_critical/snippets/legacy_token_killer.js" << 'JSEOF'
// LEGACY TOKEN KILLER - Insert at beginning of B1 - Auth Check node
// Agent: W1_03

// Kill-switch check
const legacyKillSwitch = ($env.LEGACY_SHARED_TOKEN_ENABLED || 'false').toLowerCase();
const legacyEnabled = legacyKillSwitch === 'true';

// If legacy token was attempted but disabled
const shared = ($env.WEBHOOK_SHARED_TOKEN || '').trim();
const token = $json._auth?.tokenHash ? 'present' : ($json.token || '');

if (!legacyEnabled && shared && token === shared) {
  // BLOCKED: Legacy token attempt
  return [{
    json: {
      ...$json,
      _auth: {
        ...$json._auth,
        authOk: false,
        legacyBlocked: true,
        reason: 'legacy_token_disabled'
      },
      _securityEvent: {
        event_type: 'LEGACY_TOKEN_BLOCKED',
        severity: 'HIGH',
        payload: {
          ip: $json.metadata?.ip,
          channel: $json.channel
        }
      }
    }
  }];
}

// Continue with normal auth flow...
JSEOF

echo "✅ Snippet créé: agents/wave1_critical/snippets/legacy_token_killer.js"

# 4. Afficher les instructions
echo ""
echo "=== INSTRUCTIONS MANUELLES ==="
echo ""
echo "1. VÉRIFIER que tous les clients sont migrés vers api_clients:"
echo "   psql -c 'SELECT COUNT(*) FROM api_clients WHERE active=true'"
echo ""
echo "2. METTRE À JOUR la config production:"
echo "   LEGACY_SHARED_TOKEN_ENABLED=false"
echo "   WEBHOOK_SHARED_TOKEN="
echo ""
echo "3. MODIFIER les workflows W1/W2/W3:"
echo "   - Ouvrir n8n editor"
echo "   - Ajouter le check legacy au début de B1 - Auth Check"
echo "   - Voir snippets/legacy_token_killer.js"
echo ""
echo "4. TESTER le blocage:"
echo "   curl -H 'Authorization: Bearer OLD_SHARED_TOKEN' ..."
echo "   → Doit retourner 401"
echo ""
```

## Vérification Post-Patch

### Test 1: Legacy token bloqué
```bash
# Utiliser l'ancien shared token (si connu)
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $OLD_SHARED_TOKEN" \
  "http://localhost:8080/v1/inbound/whatsapp" \
  -d '{"msg_id":"test","from":"123","text":"test","provider":"wa"}'
# Attendu: 401
```

### Test 2: Token api_clients fonctionne
```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $API_CLIENT_TOKEN" \
  "http://localhost:8080/v1/inbound/whatsapp" \
  -d '{"msg_id":"test","from":"123","text":"test","provider":"wa"}'
# Attendu: 200 ou 202
```

### Test 3: Security event logged
```sql
SELECT * FROM security_events 
WHERE event_type = 'LEGACY_TOKEN_BLOCKED' 
ORDER BY created_at DESC LIMIT 5;
```

## Rollback

En cas d'urgence (clients non migrés):
```bash
# 1. Réactiver temporairement
LEGACY_SHARED_TOKEN_ENABLED=true
WEBHOOK_SHARED_TOKEN=<ancien_token>

# 2. Redéployer

# 3. IMMÉDIATEMENT migrer les clients restants
```

## Critères de Succès
- [ ] WEBHOOK_SHARED_TOKEN est vide en prod
- [ ] LEGACY_SHARED_TOKEN_ENABLED=false en prod
- [ ] Legacy token retourne 401
- [ ] api_clients tokens fonctionnent
- [ ] security_events log LEGACY_TOKEN_BLOCKED

## Dépendances
- AGENT_W1_01 (gateway activé)
- api_clients table peuplée avec tokens valides

## Agent Suivant
→ AGENT_W2_01_AUDIT_WA_CONNECTOR
