#!/usr/bin/env node
/**
 * P2-DZ-01: Patch W14 to add ORDER and CUSTOMER admin commands
 *
 * New commands:
 * - !order list [limit] [status]
 * - !order show <id>
 * - !order noshow <id>
 * - !order cancel <id>
 * - !order delivered <id>
 * - !customer risk <user_id>
 * - !customer blacklist <user_id> [reason]
 * - !customer unblock <user_id>
 */

const fs = require('fs');
const path = require('path');

const W14_PATH = path.join(__dirname, '..', 'workflows', 'W14_ADMIN_WA_SUPPORT_CONSOLE.json');

// Read existing workflow
const workflow = JSON.parse(fs.readFileSync(W14_PATH, 'utf8'));

// Find A5 - Parse Intent node and patch it
const parseIntentNode = workflow.nodes.find(n => n.name === 'A5 - Parse Intent');
if (!parseIntentNode) {
  console.error('Could not find A5 - Parse Intent node');
  process.exit(1);
}

// Patch the jsCode to add ORDER and CUSTOMER commands
const originalCode = parseIntentNode.parameters.jsCode;

// Find the last "else action = 'UNKNOWN'" and insert before it
const insertPoint = originalCode.lastIndexOf("else action = 'UNKNOWN';");
if (insertPoint === -1) {
  console.error('Could not find insertion point in A5 - Parse Intent');
  process.exit(1);
}

const orderCustomerCode = `
// P2-DZ-01: ORDER command
else if (cmd === 'order' || cmd === 'orders' || cmd === 'cmd' || cmd === 'commande') {
  const sub = (args[0] || 'list').toLowerCase();
  if (sub === 'list' || sub === 'ls') {
    action = 'ORDER_LIST';
    e.adminOrderLimit = parseInt(args[1] || '20', 10) || 20;
    e.adminOrderStatus = (args[2] || '').toUpperCase() || null;
  } else if (sub === 'show' || sub === 'get' || sub === 'view') {
    action = 'ORDER_SHOW';
    e.adminOrderId = (args[1] || '').toString().trim();
  } else if (sub === 'noshow' || sub === 'no-show' || sub === 'ns') {
    action = 'ORDER_NOSHOW';
    e.adminOrderId = (args[1] || '').toString().trim();
  } else if (sub === 'cancel' || sub === 'annuler') {
    action = 'ORDER_CANCEL';
    e.adminOrderId = (args[1] || '').toString().trim();
    e.adminCancelReason = args.slice(2).join(' ') || 'Admin cancelled';
  } else if (sub === 'delivered' || sub === 'done' || sub === 'livré' || sub === 'livre') {
    action = 'ORDER_DELIVERED';
    e.adminOrderId = (args[1] || '').toString().trim();
  } else {
    action = 'UNKNOWN';
  }
}
// P2-DZ-01: CUSTOMER command
else if (cmd === 'customer' || cmd === 'client' || cmd === 'user') {
  const sub = (args[0] || 'risk').toLowerCase();
  if (sub === 'risk' || sub === 'risque' || sub === 'score' || sub === 'profile') {
    action = 'CUSTOMER_RISK';
    e.adminCustomerId = (args[1] || '').toString().trim();
  } else if (sub === 'blacklist' || sub === 'block' || sub === 'ban') {
    action = 'CUSTOMER_BLACKLIST';
    e.adminCustomerId = (args[1] || '').toString().trim();
    e.adminBlacklistReason = args.slice(2).join(' ') || 'Admin blacklisted';
    e.adminBlacklistDays = 30;
  } else if (sub === 'unblock' || sub === 'unban' || sub === 'unblacklist') {
    action = 'CUSTOMER_UNBLOCK';
    e.adminCustomerId = (args[1] || '').toString().trim();
  } else {
    action = 'UNKNOWN';
  }
}

`;

const newCode = originalCode.slice(0, insertPoint) + orderCustomerCode + originalCode.slice(insertPoint);
parseIntentNode.parameters.jsCode = newCode;

// Update the help text in A5 to include new commands
parseIntentNode.parameters.jsCode = parseIntentNode.parameters.jsCode.replace(
  "'*Delivery Zones*',",
  `'*Commandes (P2-DZ-01)*',
    '- !order list [limit] [status]',
    '- !order show <id>',
    '- !order noshow <id>',
    '- !order cancel <id> [reason]',
    '- !order delivered <id>',
    '',
    '*Clients*',
    '- !customer risk <phone>',
    '- !customer blacklist <phone> [reason]',
    '- !customer unblock <phone>',
    '',
    '*Delivery Zones*',`
);

// Add new nodes for ORDER and CUSTOMER commands
const baseX = 120;
const baseY = 1400; // Below existing nodes

const newNodes = [
  // ORDER_LIST
  {
    parameters: {
      conditions: { string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "ORDER_LIST" }] }
    },
    id: "ORDER_LIST_CHECK",
    name: "E1 - Is ORDER_LIST?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [baseX, baseY]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT * FROM get_recent_orders($1, $2, $3);",
      additionalFields: { queryParams: "={{[$json.restaurantId, $json.adminOrderLimit || 20, $json.adminOrderStatus || null]}}" }
    },
    id: "ORDER_LIST_DB",
    name: "E1a - Get Orders (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [baseX + 200, baseY]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const rows = $json.data || [];
if (rows.length === 0) {
  return [{json: {...$json, adminReplyText: '📋 Aucune commande trouvée.'}}];
}
const lines = rows.slice(0, 20).map((r, i) => {
  const status = r.status || 'NEW';
  const pay = r.payment_status || 'PENDING';
  const emoji = status === 'DONE' ? '✅' : status === 'CANCELLED' ? '❌' : status === 'READY' ? '🔔' : '⏳';
  const total = ((r.total_cents || 0) / 100).toFixed(0);
  const id = (r.order_id || '').toString().slice(0, 8);
  return \`\${emoji} \${id} | \${r.user_id?.slice(-4) || '????'} | \${total} DA | \${status}/\${pay}\`;
});
const reply = '*📋 Commandes récentes*\\n\\n' + lines.join('\\n') + '\\n\\n_!order show <id> pour détails_';
return [{json: {...$json, adminReplyText: reply}}];`
    },
    id: "ORDER_LIST_FORMAT",
    name: "E1b - Format Order List",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [baseX + 400, baseY]
  },

  // ORDER_SHOW
  {
    parameters: {
      conditions: { string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "ORDER_SHOW" }] }
    },
    id: "ORDER_SHOW_CHECK",
    name: "E2 - Is ORDER_SHOW?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [baseX, baseY + 120]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT * FROM get_order_details($1::uuid);",
      additionalFields: { queryParams: "={{[$json.adminOrderId]}}" }
    },
    id: "ORDER_SHOW_DB",
    name: "E2a - Get Order (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [baseX + 200, baseY + 120]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const r = ($json.data || [])[0];
if (!r) {
  return [{json: {...$json, adminReplyText: '❌ Commande non trouvée: ' + ($json.adminOrderId || 'ID manquant')}}];
}
const total = ((r.total_cents || 0) / 100).toFixed(0);
const items = r.items_json || [];
const itemsText = items.map(it => \`  • \${it.qty}x \${it.label} = \${(it.line_total/100).toFixed(0)} DA\`).join('\\n');
const trust = r.customer_trust_score || 50;
const noshow = r.customer_no_show_count || 0;
const riskEmoji = noshow > 0 ? '⚠️' : trust >= 70 ? '✅' : '⚡';

const reply = \`*📦 Commande \${r.order_id?.toString().slice(0,8)}*

*Status:* \${r.status} / \${r.payment_status}
*Mode:* \${r.payment_mode} | \${r.service_mode}
*Total:* \${total} DA

*Articles:*
\${itemsText || '(vide)'}

*Client:* \${r.user_id}
\${riskEmoji} Trust: \${trust}/100 | No-shows: \${noshow}
\${r.delivery_address ? '*Adresse:* ' + r.delivery_address : ''}

_Actions: !order noshow|cancel|delivered \${r.order_id?.toString().slice(0,8)}_\`;
return [{json: {...$json, adminReplyText: reply}}];`
    },
    id: "ORDER_SHOW_FORMAT",
    name: "E2b - Format Order",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [baseX + 400, baseY + 120]
  },

  // ORDER_NOSHOW
  {
    parameters: {
      conditions: { string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "ORDER_NOSHOW" }] }
    },
    id: "ORDER_NOSHOW_CHECK",
    name: "E3 - Is ORDER_NOSHOW?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [baseX, baseY + 240]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT * FROM mark_order_noshow($1::uuid, $2);",
      additionalFields: { queryParams: "={{[$json.adminOrderId, $json.userId]}}" }
    },
    id: "ORDER_NOSHOW_DB",
    name: "E3a - Mark No-Show (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [baseX + 200, baseY + 240]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const r = ($json.data || [])[0];
if (!r || !r.success) {
  return [{json: {...$json, adminReplyText: '❌ Erreur: ' + (r?.message || 'Commande non trouvée')}}];
}
const blacklistNote = r.blacklisted ? '\\n⛔ Client blacklisté (2+ no-shows)' : '';
const reply = \`✅ *No-show enregistré*

Commande: \${$json.adminOrderId?.slice(0,8)}
Nouveau score: \${r.new_trust_score}/100
Total no-shows: \${r.new_no_show_count}\${blacklistNote}\`;
return [{json: {...$json, adminReplyText: reply}}];`
    },
    id: "ORDER_NOSHOW_FORMAT",
    name: "E3b - Format No-Show",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [baseX + 400, baseY + 240]
  },

  // ORDER_DELIVERED
  {
    parameters: {
      conditions: { string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "ORDER_DELIVERED" }] }
    },
    id: "ORDER_DELIVERED_CHECK",
    name: "E4 - Is ORDER_DELIVERED?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [baseX, baseY + 360]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT * FROM mark_order_delivered($1::uuid, $2);",
      additionalFields: { queryParams: "={{[$json.adminOrderId, $json.userId]}}" }
    },
    id: "ORDER_DELIVERED_DB",
    name: "E4a - Mark Delivered (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [baseX + 200, baseY + 360]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const r = ($json.data || [])[0];
if (!r || !r.success) {
  return [{json: {...$json, adminReplyText: '❌ Erreur: ' + (r?.message || 'Commande non trouvée')}}];
}
const reply = \`✅ *Commande livrée!*

Commande: \${$json.adminOrderId?.slice(0,8)}
Score client: \${r.new_trust_score}/100 (+5)\`;
return [{json: {...$json, adminReplyText: reply}}];`
    },
    id: "ORDER_DELIVERED_FORMAT",
    name: "E4b - Format Delivered",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [baseX + 400, baseY + 360]
  },

  // ORDER_CANCEL
  {
    parameters: {
      conditions: { string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "ORDER_CANCEL" }] }
    },
    id: "ORDER_CANCEL_CHECK",
    name: "E5 - Is ORDER_CANCEL?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [baseX, baseY + 480]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "UPDATE orders SET status='CANCELLED', payment_status='CANCELLED', updated_at=now() WHERE order_id=$1::uuid AND status NOT IN ('DONE','CANCELLED') RETURNING order_id;",
      additionalFields: { queryParams: "={{[$json.adminOrderId]}}" }
    },
    id: "ORDER_CANCEL_DB",
    name: "E5a - Cancel Order (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [baseX + 200, baseY + 480]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const r = ($json.data || [])[0];
if (!r) {
  return [{json: {...$json, adminReplyText: '❌ Commande non trouvée ou déjà terminée'}}];
}
const reply = \`✅ *Commande annulée*\\n\\nID: \${r.order_id?.toString().slice(0,8)}\\nRaison: \${$json.adminCancelReason || 'Admin'}\`;
return [{json: {...$json, adminReplyText: reply}}];`
    },
    id: "ORDER_CANCEL_FORMAT",
    name: "E5b - Format Cancel",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [baseX + 400, baseY + 480]
  },

  // CUSTOMER_RISK
  {
    parameters: {
      conditions: { string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "CUSTOMER_RISK" }] }
    },
    id: "CUSTOMER_RISK_CHECK",
    name: "F1 - Is CUSTOMER_RISK?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [baseX, baseY + 600]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT * FROM get_customer_risk_profile($1);",
      additionalFields: { queryParams: "={{[$json.adminCustomerId]}}" }
    },
    id: "CUSTOMER_RISK_DB",
    name: "F1a - Get Risk (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [baseX + 200, baseY + 600]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const r = ($json.data || [])[0];
if (!r) {
  return [{json: {...$json, adminReplyText: '❌ Client non trouvé: ' + $json.adminCustomerId}}];
}
const riskEmoji = {
  'BLACKLISTED': '⛔',
  'HIGH': '🔴',
  'MEDIUM': '🟡',
  'LOW': '🟢',
  'TRUSTED': '✅',
  'NEW': '🆕'
}[r.risk_level] || '❓';

const blacklistInfo = r.soft_blacklisted
  ? \`\\n⛔ *BLACKLISTÉ*\\nRaison: \${r.blacklist_reason || 'N/A'}\\nJusqu'au: \${r.blacklist_until ? new Date(r.blacklist_until).toLocaleDateString('fr') : 'N/A'}\`
  : '';

const reply = \`*👤 Profil Client*

📱 \${r.user_id}
\${riskEmoji} Risque: *\${r.risk_level}*

📊 *Score:* \${r.trust_score}/100
📦 Commandes: \${r.total_orders} total
✅ Livrées: \${r.completed_orders}
❌ Annulées: \${r.cancelled_orders}
🚫 No-shows: \${r.no_show_count}

💳 Acompte requis: \${r.requires_deposit ? 'Oui' : 'Non'}\${blacklistInfo}

_!customer blacklist/unblock \${r.user_id}_\`;
return [{json: {...$json, adminReplyText: reply}}];`
    },
    id: "CUSTOMER_RISK_FORMAT",
    name: "F1b - Format Risk",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [baseX + 400, baseY + 600]
  },

  // CUSTOMER_BLACKLIST
  {
    parameters: {
      conditions: { string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "CUSTOMER_BLACKLIST" }] }
    },
    id: "CUSTOMER_BLACKLIST_CHECK",
    name: "F2 - Is CUSTOMER_BLACKLIST?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [baseX, baseY + 720]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT * FROM blacklist_customer($1, $2::uuid, $3, $4, $5);",
      additionalFields: { queryParams: "={{[$json.adminCustomerId, $json.tenantId, $json.adminBlacklistReason, $json.adminBlacklistDays || 30, $json.userId]}}" }
    },
    id: "CUSTOMER_BLACKLIST_DB",
    name: "F2a - Blacklist (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [baseX + 200, baseY + 720]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const r = ($json.data || [])[0];
const reply = r?.success
  ? \`⛔ *Client blacklisté*\\n\\n\${$json.adminCustomerId}\\nRaison: \${$json.adminBlacklistReason}\\nDurée: \${$json.adminBlacklistDays || 30} jours\`
  : '❌ Erreur: ' + (r?.message || 'Échec blacklist');
return [{json: {...$json, adminReplyText: reply}}];`
    },
    id: "CUSTOMER_BLACKLIST_FORMAT",
    name: "F2b - Format Blacklist",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [baseX + 400, baseY + 720]
  },

  // CUSTOMER_UNBLOCK
  {
    parameters: {
      conditions: { string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "CUSTOMER_UNBLOCK" }] }
    },
    id: "CUSTOMER_UNBLOCK_CHECK",
    name: "F3 - Is CUSTOMER_UNBLOCK?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [baseX, baseY + 840]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT * FROM unblacklist_customer($1, $2);",
      additionalFields: { queryParams: "={{[$json.adminCustomerId, $json.userId]}}" }
    },
    id: "CUSTOMER_UNBLOCK_DB",
    name: "F3a - Unblock (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [baseX + 200, baseY + 840]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const r = ($json.data || [])[0];
const reply = r?.success
  ? \`✅ *Client débloqué*\\n\\n\${$json.adminCustomerId}\`
  : '❌ ' + (r?.message || 'Client non trouvé');
return [{json: {...$json, adminReplyText: reply}}];`
    },
    id: "CUSTOMER_UNBLOCK_FORMAT",
    name: "F3b - Format Unblock",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [baseX + 400, baseY + 840]
  }
];

// Add new nodes
workflow.nodes.push(...newNodes);

// Find B1 - Is HELP? node to get routing pattern
// We need to add connections from A5 (via its false branch cascade)

// Find the node that routes after A5 - Parse Intent
// In the existing workflow, after B6 - Is UNKNOWN? there's a cascade of checks
// We need to add our new checks to this cascade

// Find existing connection patterns
const a5Node = workflow.nodes.find(n => n.name === 'A5 - Parse Intent');
const b1Node = workflow.nodes.find(n => n.name === 'B1 - Is HELP?');

// Add new connections
// From the cascade (after existing checks), add connections to our new nodes
// Each new IF node should:
// - If true: go to DB node
// - If false: go to next check or END

// Find the last check in the cascade (before UNKNOWN)
// We'll add our checks after the existing ones

// Find nodes that connect to O0 - Build Admin Outbox
const outboxNode = workflow.nodes.find(n => n.name === 'O0 - Build Admin Outbox');

// Add connections for new nodes
const newConnections = {
  // ORDER_LIST chain
  "E1 - Is ORDER_LIST?": {
    main: [
      [{ node: "E1a - Get Orders (DB)", type: "main", index: 0 }],
      [{ node: "E2 - Is ORDER_SHOW?", type: "main", index: 0 }]
    ]
  },
  "E1a - Get Orders (DB)": {
    main: [[{ node: "E1b - Format Order List", type: "main", index: 0 }]]
  },
  "E1b - Format Order List": {
    main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]]
  },

  // ORDER_SHOW chain
  "E2 - Is ORDER_SHOW?": {
    main: [
      [{ node: "E2a - Get Order (DB)", type: "main", index: 0 }],
      [{ node: "E3 - Is ORDER_NOSHOW?", type: "main", index: 0 }]
    ]
  },
  "E2a - Get Order (DB)": {
    main: [[{ node: "E2b - Format Order", type: "main", index: 0 }]]
  },
  "E2b - Format Order": {
    main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]]
  },

  // ORDER_NOSHOW chain
  "E3 - Is ORDER_NOSHOW?": {
    main: [
      [{ node: "E3a - Mark No-Show (DB)", type: "main", index: 0 }],
      [{ node: "E4 - Is ORDER_DELIVERED?", type: "main", index: 0 }]
    ]
  },
  "E3a - Mark No-Show (DB)": {
    main: [[{ node: "E3b - Format No-Show", type: "main", index: 0 }]]
  },
  "E3b - Format No-Show": {
    main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]]
  },

  // ORDER_DELIVERED chain
  "E4 - Is ORDER_DELIVERED?": {
    main: [
      [{ node: "E4a - Mark Delivered (DB)", type: "main", index: 0 }],
      [{ node: "E5 - Is ORDER_CANCEL?", type: "main", index: 0 }]
    ]
  },
  "E4a - Mark Delivered (DB)": {
    main: [[{ node: "E4b - Format Delivered", type: "main", index: 0 }]]
  },
  "E4b - Format Delivered": {
    main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]]
  },

  // ORDER_CANCEL chain
  "E5 - Is ORDER_CANCEL?": {
    main: [
      [{ node: "E5a - Cancel Order (DB)", type: "main", index: 0 }],
      [{ node: "F1 - Is CUSTOMER_RISK?", type: "main", index: 0 }]
    ]
  },
  "E5a - Cancel Order (DB)": {
    main: [[{ node: "E5b - Format Cancel", type: "main", index: 0 }]]
  },
  "E5b - Format Cancel": {
    main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]]
  },

  // CUSTOMER_RISK chain
  "F1 - Is CUSTOMER_RISK?": {
    main: [
      [{ node: "F1a - Get Risk (DB)", type: "main", index: 0 }],
      [{ node: "F2 - Is CUSTOMER_BLACKLIST?", type: "main", index: 0 }]
    ]
  },
  "F1a - Get Risk (DB)": {
    main: [[{ node: "F1b - Format Risk", type: "main", index: 0 }]]
  },
  "F1b - Format Risk": {
    main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]]
  },

  // CUSTOMER_BLACKLIST chain
  "F2 - Is CUSTOMER_BLACKLIST?": {
    main: [
      [{ node: "F2a - Blacklist (DB)", type: "main", index: 0 }],
      [{ node: "F3 - Is CUSTOMER_UNBLOCK?", type: "main", index: 0 }]
    ]
  },
  "F2a - Blacklist (DB)": {
    main: [[{ node: "F2b - Format Blacklist", type: "main", index: 0 }]]
  },
  "F2b - Format Blacklist": {
    main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]]
  },

  // CUSTOMER_UNBLOCK chain (last in chain, false goes nowhere)
  "F3 - Is CUSTOMER_UNBLOCK?": {
    main: [
      [{ node: "F3a - Unblock (DB)", type: "main", index: 0 }],
      [] // End of chain
    ]
  },
  "F3a - Unblock (DB)": {
    main: [[{ node: "F3b - Format Unblock", type: "main", index: 0 }]]
  },
  "F3b - Format Unblock": {
    main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]]
  }
};

// Merge new connections
Object.assign(workflow.connections, newConnections);

// Find the last existing check node and connect its false branch to our first check
// Looking for D8 (or the last D* node before STATS nodes)
const existingChecks = Object.keys(workflow.connections).filter(k => k.startsWith('D') && k.includes('Is'));
const statsCheck = workflow.nodes.find(n => n.name && n.name.includes('Is STATS'));

if (statsCheck) {
  // Find what connects to STATS check and insert our chain before it
  for (const [nodeName, conn] of Object.entries(workflow.connections)) {
    if (conn.main && conn.main[1]) {
      const falseConn = conn.main[1];
      if (falseConn.some(c => c.node === statsCheck.name)) {
        // Insert our chain here
        conn.main[1] = [{ node: "E1 - Is ORDER_LIST?", type: "main", index: 0 }];
        console.log(`Inserted ORDER chain after ${nodeName}`);
        break;
      }
    }
  }
} else {
  // Fallback: find the last D* check and connect after it
  const lastDCheck = existingChecks.sort().pop();
  if (lastDCheck && workflow.connections[lastDCheck]?.main?.[1]) {
    workflow.connections[lastDCheck].main[1] = [{ node: "E1 - Is ORDER_LIST?", type: "main", index: 0 }];
    console.log(`Inserted ORDER chain after ${lastDCheck}`);
  }
}

// Write updated workflow
fs.writeFileSync(W14_PATH, JSON.stringify(workflow, null, 2));
console.log('✅ W14 patched with ORDER and CUSTOMER commands');
console.log('   - !order list/show/noshow/cancel/delivered');
console.log('   - !customer risk/blacklist/unblock');
