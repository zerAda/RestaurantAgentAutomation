# AGENT 04 — Admin WhatsApp Audit Log (P0-SUP-01)

## Mission
Add comprehensive audit logging to W14 Admin WhatsApp Console for compliance and traceability.

## Priority
**P0 - HIGH** - Required for compliance and support traceability.

## Problem Statement
- W14 allows operators to perform actions via WhatsApp (reply, close, assign tickets)
- Currently NO audit trail for these actions
- Cannot trace who did what, when, on which ticket
- Compliance risk for support operations

## Solution
1. Create `admin_wa_audit_log` table
2. Insert audit record for every W14 command
3. Add `ADMIN_WA_AUDIT_ENABLED` flag
4. Include actor, action, target, timestamp, metadata

## Files Modified
- `db/migrations/2026-01-23_p0_sup01_admin_wa_audit.sql`
- `workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json`
- `config/.env.example`

## Implementation

### Migration SQL
```sql
CREATE TABLE IF NOT EXISTS admin_wa_audit_log (
  id              bigserial PRIMARY KEY,
  tenant_id       uuid REFERENCES tenants(tenant_id) ON DELETE SET NULL,
  restaurant_id   uuid REFERENCES restaurants(restaurant_id) ON DELETE SET NULL,
  actor_phone     text NOT NULL,
  actor_role      text NOT NULL,
  action          text NOT NULL,
  target_type     text,           -- 'ticket', 'order', 'customer', etc.
  target_id       text,           -- ticket_id, order_id, etc.
  command_raw     text,           -- original command text
  metadata_json   jsonb DEFAULT '{}'::jsonb,
  ip_address      text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_admin_wa_audit_tenant_time 
  ON admin_wa_audit_log(tenant_id, created_at DESC);
CREATE INDEX idx_admin_wa_audit_actor_time 
  ON admin_wa_audit_log(actor_phone, created_at DESC);
CREATE INDEX idx_admin_wa_audit_target 
  ON admin_wa_audit_log(target_type, target_id);
```

### .env.example additions
```env
# Admin WhatsApp audit logging
ADMIN_WA_AUDIT_ENABLED=true
```

### W14 Audit Insert (after each command)
```javascript
// Insert audit log for every admin action
const auditEnabled = ($env.ADMIN_WA_AUDIT_ENABLED || 'true').toLowerCase() === 'true';

if (auditEnabled) {
  const auditRecord = {
    tenant_id: tenantId,
    restaurant_id: restaurantId,
    actor_phone: adminPhone,
    actor_role: adminRole,
    action: command,  // 'take', 'reply', 'close', 'assign', etc.
    target_type: 'ticket',
    target_id: ticketId,
    command_raw: rawMessage,
    metadata_json: JSON.stringify({
      reply_text: replyText || null,
      assignee: assignee || null,
      status_change: statusChange || null
    }),
    ip_address: ip || null
  };
  
  // Insert via Postgres node
  await $node["Insert Audit"].execute(auditRecord);
}
```

### Supported Actions to Audit
| Command | Action | Target Type | Notes |
|---------|--------|-------------|-------|
| `!take #123` | `take` | `ticket` | Assign to self |
| `!reply #123 text` | `reply` | `ticket` | Send reply |
| `!close #123` | `close` | `ticket` | Close ticket |
| `!assign #123 @agent` | `assign` | `ticket` | Assign to other |
| `!status #123 status` | `status_change` | `ticket` | Change status |
| `!escalate #123` | `escalate` | `ticket` | Escalate ticket |
| `!note #123 text` | `note` | `ticket` | Add internal note |

## Rollback
Set `ADMIN_WA_AUDIT_ENABLED=false` to disable logging (table remains).

## Tests
```sql
-- Verify audit records exist
SELECT * FROM admin_wa_audit_log 
WHERE created_at > now() - interval '1 hour'
ORDER BY created_at DESC;

-- Count actions per actor
SELECT actor_phone, action, COUNT(*) 
FROM admin_wa_audit_log 
GROUP BY actor_phone, action;
```

## Validation Checklist
- [ ] Every W14 command creates audit record
- [ ] Audit includes actor, action, target, timestamp
- [ ] Metadata captures command-specific details
- [ ] Retention job cleans old records (90 days default)
- [ ] Audit query performance acceptable
