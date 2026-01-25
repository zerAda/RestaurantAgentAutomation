# AGENT_W2_01 — Audit WA Connector (HIGH)

## Mission
**BRANCHER** l'audit trail dans W14 qui existe en DB mais n'est PAS connecté.

## Problème Identifié (Audit V4)
```
Impact : actions admin via WhatsApp = aucune traçabilité → en incident/fraude tu es aveugle.
Preuve : migration crée admin_wa_audit_log, mais W14 n'insère rien dedans.
```

## Analyse

### Ce qui existe déjà ✅
- Table `admin_wa_audit_log` créée par migration
- Fonction `insert_admin_wa_audit()` disponible
- W14 workflow existe et fonctionne

### Ce qui manque ❌
- Aucun node dans W14 n'appelle `insert_admin_wa_audit()`
- Les actions admin passent sans trace

## Solution: Ajouter des nodes d'audit dans W14

### Structure W14 actuelle (simplifiée)
```
Webhook → Parse Command → Router
                           ├── !tickets → List tickets
                           ├── !take #id → Take ticket
                           ├── !reply #id msg → Reply
                           ├── !close #id → Close ticket
                           └── ... autres commandes
```

### Structure W14 après patch
```
Webhook → Parse Command → Router
                           ├── !tickets → List tickets → [AUDIT]
                           ├── !take #id → Take ticket → [AUDIT]
                           ├── !reply #id msg → Reply → [AUDIT]
                           ├── !close #id → Close ticket → [AUDIT]
                           └── ... autres commandes → [AUDIT]
```

## Code du Node d'Audit

### audit_wa_action.js (à ajouter après chaque action)
```javascript
// ============================================
// AUDIT NODE - Insert into admin_wa_audit_log
// Add this after each command action in W14
// ============================================

const auditEnabled = ($env.ADMIN_WA_AUDIT_ENABLED || 'true').toLowerCase() === 'true';

if (!auditEnabled) {
  return [$json];
}

// Extract action info from context
const tenantId = $json.tenantId || $json.tenant_id || null;
const restaurantId = $json.restaurantId || $json.restaurant_id || null;
const actorPhone = $json.adminPhone || $json.actor_phone || $json.from || '';
const actorRole = $json.adminRole || $json.actor_role || 'admin';
const action = $json.command || $json.action || 'unknown';
const targetType = $json.targetType || 'ticket';
const targetId = $json.ticketId || $json.target_id || null;
const commandRaw = $json.rawMessage || $json.command_raw || '';
const success = $json.success !== false;
const errorMessage = $json.error || null;

// Build metadata
const metadata = {
  reply_text: $json.replyText || null,
  assignee: $json.assignee || null,
  status_change: $json.statusChange || null,
  previous_status: $json.previousStatus || null,
  workflow_execution_id: $execution?.id || null
};

// Return with audit payload for next Postgres node
return [{
  json: {
    ...$json,
    _audit: {
      tenant_id: tenantId,
      restaurant_id: restaurantId,
      actor_phone: actorPhone,
      actor_role: actorRole,
      action: action,
      target_type: targetType,
      target_id: targetId,
      command_raw: commandRaw,
      metadata_json: JSON.stringify(metadata),
      success: success,
      error_message: errorMessage
    }
  }
}];
```

### SQL Query for Postgres Node
```sql
INSERT INTO admin_wa_audit_log (
  tenant_id, restaurant_id, actor_phone, actor_role,
  action, target_type, target_id, command_raw,
  metadata_json, success, error_message
) VALUES (
  $1::uuid, $2::uuid, $3, $4,
  $5, $6, $7, $8,
  $9::jsonb, $10, $11
) RETURNING id;
```

Query params:
```javascript
[
  $json._audit.tenant_id,
  $json._audit.restaurant_id,
  $json._audit.actor_phone,
  $json._audit.actor_role,
  $json._audit.action,
  $json._audit.target_type,
  $json._audit.target_id,
  $json._audit.command_raw,
  $json._audit.metadata_json,
  $json._audit.success,
  $json._audit.error_message
]
```

## Script d'Application

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== AGENT_W2_01: Audit WA Connector ==="

PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$0")")")"

# 1. Vérifier que la table existe
echo "Vérification de la table admin_wa_audit_log..."

# 2. Vérifier que le flag est dans .env
if grep -q "ADMIN_WA_AUDIT_ENABLED" "$PROJECT_ROOT/config/.env.example"; then
    echo "✅ Flag ADMIN_WA_AUDIT_ENABLED présent"
else
    echo "Ajout du flag..."
    echo "" >> "$PROJECT_ROOT/config/.env.example"
    echo "# Admin WA Audit (AGENT_W2_01)" >> "$PROJECT_ROOT/config/.env.example"
    echo "ADMIN_WA_AUDIT_ENABLED=true" >> "$PROJECT_ROOT/config/.env.example"
fi

# 3. Créer le snippet
mkdir -p "$PROJECT_ROOT/agents/wave2_high/snippets"

cat > "$PROJECT_ROOT/agents/wave2_high/snippets/audit_wa_action.js" << 'JSEOF'
// AUDIT NODE for W14 - Add after each command action
const auditEnabled = ($env.ADMIN_WA_AUDIT_ENABLED || 'true').toLowerCase() === 'true';
if (!auditEnabled) return [$json];

const tenantId = $json.tenantId || null;
const restaurantId = $json.restaurantId || null;
const actorPhone = $json.adminPhone || $json.from || '';
const actorRole = $json.adminRole || 'admin';
const action = $json.command || 'unknown';
const targetId = $json.ticketId || null;
const commandRaw = $json.rawMessage || '';
const success = $json.success !== false;

return [{json: {...$json, _audit: {
  tenant_id: tenantId,
  restaurant_id: restaurantId,
  actor_phone: actorPhone,
  actor_role: actorRole,
  action: action,
  target_type: 'ticket',
  target_id: targetId,
  command_raw: commandRaw,
  metadata_json: JSON.stringify({reply: $json.replyText || null}),
  success: success,
  error_message: $json.error || null
}}}];
JSEOF

echo "✅ Snippet créé: agents/wave2_high/snippets/audit_wa_action.js"

# 4. Instructions
echo ""
echo "=== INSTRUCTIONS MANUELLES ==="
echo ""
echo "1. Ouvrir W14_ADMIN_WA_SUPPORT_CONSOLE.json dans n8n"
echo ""
echo "2. Pour CHAQUE branche de commande (!take, !reply, !close, etc.):"
echo "   a. Ajouter un Code node avec audit_wa_action.js"
echo "   b. Ajouter un Postgres node avec INSERT INTO admin_wa_audit_log"
echo ""
echo "3. Sauvegarder et activer le workflow"
echo ""
echo "4. Tester avec une commande admin:"
echo "   !take #123"
echo ""
echo "5. Vérifier l'audit:"
echo "   psql -c \"SELECT * FROM admin_wa_audit_log ORDER BY created_at DESC LIMIT 5\""
```

## Actions à Auditer

| Commande | Action | target_type | Metadata |
|----------|--------|-------------|----------|
| `!tickets` | `list_tickets` | - | filters |
| `!take #id` | `take` | ticket | - |
| `!reply #id msg` | `reply` | ticket | reply_text |
| `!close #id` | `close` | ticket | - |
| `!assign #id @agent` | `assign` | ticket | assignee |
| `!escalate #id` | `escalate` | ticket | - |
| `!note #id text` | `note` | ticket | note_text |
| `!status #id status` | `status_change` | ticket | new_status |
| `!zone create ...` | `zone_create` | zone | zone_data |
| `!template set ...` | `template_update` | template | template_data |

## Vérification Post-Patch

### Test 1: Commande admin crée audit
```bash
# Envoyer une commande admin via WhatsApp (ou test direct)
# Puis vérifier:
psql -c "SELECT id, actor_phone, action, target_id, created_at 
         FROM admin_wa_audit_log 
         ORDER BY created_at DESC LIMIT 5"
```

### Test 2: Comptage par action
```sql
SELECT action, COUNT(*) 
FROM admin_wa_audit_log 
WHERE created_at > now() - interval '1 hour'
GROUP BY action;
```

## Rollback
```env
ADMIN_WA_AUDIT_ENABLED=false
```

## Critères de Succès
- [ ] Chaque commande W14 crée un enregistrement audit
- [ ] Les champs actor, action, target sont remplis
- [ ] Les erreurs sont loggées avec success=false
- [ ] Requêtes d'audit performantes

## Agent Suivant
→ AGENT_W2_02_RATE_LIMIT_ENFORCER
