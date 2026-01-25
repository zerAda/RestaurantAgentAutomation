// ============================================
// AUDIT WA ACTION NODE
// Agent: W2_01 - Audit WA Connector
// 
// INSTALLATION:
// Add this as a Code node AFTER each command action in W14
// Then connect to a Postgres node that inserts into admin_wa_audit_log
// ============================================

// Check if audit is enabled
const auditEnabled = ($env.ADMIN_WA_AUDIT_ENABLED || 'true').toLowerCase() === 'true';

if (!auditEnabled) {
  // Audit disabled - pass through without modification
  return [{ json: $json }];
}

// === EXTRACT CONTEXT ===

// Tenant/Restaurant context
const tenantId = $json.tenantId || $json.tenant_id || $json.context?.tenantId || null;
const restaurantId = $json.restaurantId || $json.restaurant_id || $json.context?.restaurantId || null;

// Actor information (admin performing the action)
const actorPhone = $json.adminPhone || $json.actor_phone || $json.from || $json.userId || '';
const actorRole = $json.adminRole || $json.actor_role || $json.role || 'admin';

// Action details
const action = $json.command || $json.action || $json.parsedCommand?.action || 'unknown';
const targetType = $json.targetType || $json.target_type || 'ticket';
const targetId = $json.ticketId || $json.target_id || $json.orderId || $json.zoneId || null;

// Raw command for audit trail
const commandRaw = $json.rawMessage || $json.command_raw || $json.text || '';

// Success/error tracking
const success = $json.success !== false && !$json.error;
const errorMessage = $json.error || $json.errorMessage || null;

// === BUILD METADATA ===
const metadata = {
  // Reply content (for !reply commands)
  reply_text: $json.replyText || $json.reply_text || null,
  
  // Assignment info (for !assign commands)
  assignee: $json.assignee || $json.assigned_to || null,
  
  // Status changes (for !status, !close commands)
  status_change: $json.statusChange || $json.new_status || null,
  previous_status: $json.previousStatus || $json.old_status || null,
  
  // Workflow context
  workflow_execution_id: $execution?.id || null,
  workflow_name: $workflow?.name || 'W14_ADMIN_WA_SUPPORT_CONSOLE',
  
  // Additional context based on action type
  ...(action === 'zone_create' || action === 'zone_update' ? {
    zone_data: $json.zoneData || null
  } : {}),
  
  ...(action === 'template_update' ? {
    template_key: $json.templateKey || null,
    template_locale: $json.templateLocale || null
  } : {}),
  
  // Timestamp
  action_timestamp: new Date().toISOString()
};

// === BUILD AUDIT PAYLOAD ===
const auditPayload = {
  tenant_id: tenantId,
  restaurant_id: restaurantId,
  actor_phone: actorPhone,
  actor_role: actorRole,
  action: action,
  target_type: targetType,
  target_id: targetId ? String(targetId) : null,
  command_raw: commandRaw.substring(0, 500), // Limit length
  metadata_json: JSON.stringify(metadata),
  success: success,
  error_message: errorMessage
};

// === RETURN WITH AUDIT DATA ===
return [{
  json: {
    ...$json,
    _audit: auditPayload,
    _auditReady: true
  }
}];

// ============================================
// NEXT STEP: Connect this to a Postgres node with:
// 
// Query:
// INSERT INTO admin_wa_audit_log (
//   tenant_id, restaurant_id, actor_phone, actor_role,
//   action, target_type, target_id, command_raw,
//   metadata_json, success, error_message
// ) VALUES (
//   $1::uuid, $2::uuid, $3, $4,
//   $5, $6, $7, $8,
//   $9::jsonb, $10, $11
// ) RETURNING id;
//
// Parameters:
// {{ $json._audit.tenant_id }}
// {{ $json._audit.restaurant_id }}
// {{ $json._audit.actor_phone }}
// {{ $json._audit.actor_role }}
// {{ $json._audit.action }}
// {{ $json._audit.target_type }}
// {{ $json._audit.target_id }}
// {{ $json._audit.command_raw }}
// {{ $json._audit.metadata_json }}
// {{ $json._audit.success }}
// {{ $json._audit.error_message }}
// ============================================
