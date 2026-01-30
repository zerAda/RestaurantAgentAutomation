#!/usr/bin/env node
/**
 * P2-02: Patch W14 to add STATUS, FLAGS, DLQ command handlers
 */
const fs = require('fs');
const path = require('path');

const W14_PATH = path.join(__dirname, '..', 'workflows', 'W14_ADMIN_WA_SUPPORT_CONSOLE.json');

const wf = JSON.parse(fs.readFileSync(W14_PATH, 'utf8'));

// Generate unique IDs
function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0;
    return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
  });
}

// New nodes for P2-02 commands
const newNodes = [
  // ========== STATUS ==========
  {
    parameters: {
      conditions: {
        string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "STATUS" }]
      }
    },
    id: "D1_IS_STATUS",
    name: "D1 - Is STATUS?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [120, 700]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT get_system_status() AS status;",
      additionalFields: {}
    },
    id: "D1A_STATUS_DB",
    name: "D1a - Get Status (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [320, 700]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const e = $json;
const statusData = e.data?.[0]?.status || {};
const ts = statusData.timestamp || new Date().toISOString();
const db = statusData.database || {};
const counts = statusData.counts || {};
const flags = statusData.flags || {};

let txt = '*System Status*\\n';
txt += '─────────────\\n';
txt += \`⏰ \${ts}\\n\\n\`;

txt += '*Database*\\n';
txt += \`  Connected: \${db.connected ? '✅' : '❌'}\\n\\n\`;

txt += '*Counts*\\n';
txt += \`  Pending outbound: \${counts.pending_outbound || 0}\\n\`;
txt += \`  DLQ messages: \${counts.dlq_messages || 0}\\n\`;
txt += \`  Active tickets: \${counts.active_tickets || 0}\\n\`;
txt += \`  Conversations (24h): \${counts.conversations_24h || 0}\\n\\n\`;

txt += '*Flags*\\n';
for (const [k, v] of Object.entries(flags)) {
  const icon = (v === 'true' || v === true) ? '🟢' : (v === 'false' || v === false) ? '🔴' : '⚪';
  txt += \`  \${icon} \${k}: \${v}\\n\`;
}

return [{json:{...e, adminReplyText: txt.trim()}}];`
    },
    id: "D1B_FORMAT_STATUS",
    name: "D1b - Format Status",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [520, 700]
  },

  // ========== FLAGS LIST ==========
  {
    parameters: {
      conditions: {
        string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "FLAGS_LIST" }]
      }
    },
    id: "D2_IS_FLAGS_LIST",
    name: "D2 - Is FLAGS_LIST?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [120, 820]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT flag_key, flag_value, description, updated_at FROM system_flags ORDER BY flag_key;",
      additionalFields: {}
    },
    id: "D2A_FLAGS_LIST_DB",
    name: "D2a - Get Flags (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [320, 820]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const e = $json;
const rows = e.data || [];
if (!rows.length) {
  return [{json:{...e, adminReplyText: 'No system flags configured.'}}];
}
let txt = '*System Flags*\\n';
txt += '─────────────\\n';
for (const r of rows) {
  const icon = (r.flag_value === 'true') ? '🟢' : (r.flag_value === 'false') ? '🔴' : '⚪';
  txt += \`\${icon} *\${r.flag_key}*: \${r.flag_value}\\n\`;
  if (r.description) txt += \`   _\${r.description}_\\n\`;
}
txt += '\\n➡️ !flags set <KEY> <VALUE>';
return [{json:{...e, adminReplyText: txt.trim()}}];`
    },
    id: "D2B_FORMAT_FLAGS_LIST",
    name: "D2b - Format Flags List",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [520, 820]
  },

  // ========== FLAGS SET ==========
  {
    parameters: {
      conditions: {
        string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "FLAGS_SET" }]
      }
    },
    id: "D3_IS_FLAGS_SET",
    name: "D3 - Is FLAGS_SET?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [120, 940]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "UPDATE system_flags SET flag_value=$2, updated_at=now(), updated_by=$3 WHERE flag_key=$1 RETURNING flag_key, flag_value;",
      additionalFields: {
        queryParams: "={{[$json.adminFlagKey, $json.adminFlagValue, $json.userId]}}"
      }
    },
    id: "D3A_FLAGS_SET_DB",
    name: "D3a - Set Flag (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [320, 940]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const e = $json;
const rows = e.data || [];
if (!rows.length) {
  return [{json:{...e, adminReplyText: '❌ Flag not found: ' + (e.adminFlagKey || '?')}}];
}
const r = rows[0];
const icon = (r.flag_value === 'true') ? '🟢' : (r.flag_value === 'false') ? '🔴' : '⚪';
return [{json:{...e, adminReplyText: \`✅ Flag updated\\n\${icon} *\${r.flag_key}* = \${r.flag_value}\`}}];`
    },
    id: "D3B_FORMAT_FLAGS_SET",
    name: "D3b - Format Flag Set",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [520, 940]
  },

  // ========== DLQ LIST ==========
  {
    parameters: {
      conditions: {
        string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "DLQ_LIST" }]
      }
    },
    id: "D4_IS_DLQ_LIST",
    name: "D4 - Is DLQ_LIST?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [120, 1060]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT * FROM get_dlq_messages($1, 0);",
      additionalFields: {
        queryParams: "={{[$json.adminDlqLimit || 20]}}"
      }
    },
    id: "D4A_DLQ_LIST_DB",
    name: "D4a - Get DLQ List (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [320, 1060]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const e = $json;
const rows = e.data || [];
if (!rows.length) {
  return [{json:{...e, adminReplyText: '✅ DLQ is empty. No failed messages.'}}];
}
let txt = '*DLQ Messages (' + rows.length + ')*\\n';
txt += '─────────────\\n';
for (const r of rows.slice(0, 15)) {
  const age = r.created_at ? new Date(r.created_at).toISOString().slice(0,16).replace('T',' ') : '?';
  txt += \`#\${r.outbound_id} | \${r.channel} | \${r.user_id?.slice(0,12) || '?'} | att:\${r.attempts}\\n\`;
  txt += \`   err: \${(r.last_error || '?').slice(0,50)}\\n\`;
}
if (rows.length > 15) txt += \`... and \${rows.length - 15} more\\n\`;
txt += '\\n➡️ !dlq show <id> | !dlq replay <id> | !dlq drop <id>';
return [{json:{...e, adminReplyText: txt.trim()}}];`
    },
    id: "D4B_FORMAT_DLQ_LIST",
    name: "D4b - Format DLQ List",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [520, 1060]
  },

  // ========== DLQ SHOW ==========
  {
    parameters: {
      conditions: {
        string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "DLQ_SHOW" }]
      }
    },
    id: "D5_IS_DLQ_SHOW",
    name: "D5 - Is DLQ_SHOW?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [120, 1180]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT outbound_id, channel, user_id, restaurant_id, status, attempts, last_error, created_at, correlation_id, payload_json FROM outbound_messages WHERE outbound_id=$1 AND status='DLQ';",
      additionalFields: {
        queryParams: "={{[$json.adminDlqId]}}"
      }
    },
    id: "D5A_DLQ_SHOW_DB",
    name: "D5a - Get DLQ Item (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [320, 1180]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const e = $json;
const rows = e.data || [];
if (!rows.length) {
  return [{json:{...e, adminReplyText: '❌ DLQ message not found: #' + (e.adminDlqId || '?')}}];
}
const r = rows[0];
let txt = '*DLQ Message #' + r.outbound_id + '*\\n';
txt += '─────────────\\n';
txt += \`Channel: \${r.channel}\\n\`;
txt += \`User: \${r.user_id}\\n\`;
txt += \`Attempts: \${r.attempts}\\n\`;
txt += \`Created: \${r.created_at}\\n\`;
txt += \`Correlation: \${r.correlation_id || '-'}\\n\\n\`;
txt += '*Last Error*\\n\${r.last_error || '-'}\\n\\n\`;
txt += '*Payload*\\n';
try {
  const p = typeof r.payload_json === 'string' ? JSON.parse(r.payload_json) : r.payload_json;
  txt += JSON.stringify(p, null, 2).slice(0, 500);
} catch { txt += String(r.payload_json).slice(0, 500); }
txt += '\\n\\n➡️ !dlq replay ' + r.outbound_id + ' | !dlq drop ' + r.outbound_id;
return [{json:{...e, adminReplyText: txt.trim()}}];`
    },
    id: "D5B_FORMAT_DLQ_SHOW",
    name: "D5b - Format DLQ Show",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [520, 1180]
  },

  // ========== DLQ REPLAY ==========
  {
    parameters: {
      conditions: {
        string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "DLQ_REPLAY" }]
      }
    },
    id: "D6_IS_DLQ_REPLAY",
    name: "D6 - Is DLQ_REPLAY?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [120, 1300]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT replay_dlq_message($1, $2) AS result;",
      additionalFields: {
        queryParams: "={{[$json.adminDlqId, $json.userId]}}"
      }
    },
    id: "D6A_DLQ_REPLAY_DB",
    name: "D6a - Replay DLQ (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [320, 1300]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const e = $json;
const result = e.data?.[0]?.result || {};
if (!result.success) {
  return [{json:{...e, adminReplyText: '❌ Replay failed: ' + (result.error || 'Unknown error')}}];
}
return [{json:{...e, adminReplyText: '✅ Message #' + result.outbound_id + ' queued for retry.\\nNew status: ' + result.new_status}}];`
    },
    id: "D6B_FORMAT_DLQ_REPLAY",
    name: "D6b - Format DLQ Replay",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [520, 1300]
  },

  // ========== DLQ DROP ==========
  {
    parameters: {
      conditions: {
        string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "DLQ_DROP" }]
      }
    },
    id: "D7_IS_DLQ_DROP",
    name: "D7 - Is DLQ_DROP?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [120, 1420]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT drop_dlq_message($1, $2) AS result;",
      additionalFields: {
        queryParams: "={{[$json.adminDlqId, $json.userId]}}"
      }
    },
    id: "D7A_DLQ_DROP_DB",
    name: "D7a - Drop DLQ (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [320, 1420]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const e = $json;
const result = e.data?.[0]?.result || {};
if (!result.success) {
  return [{json:{...e, adminReplyText: '❌ Drop failed: ' + (result.error || 'Unknown error')}}];
}
return [{json:{...e, adminReplyText: '🗑️ Message #' + result.outbound_id + ' permanently dropped.\\nNew status: ' + result.new_status}}];`
    },
    id: "D7B_FORMAT_DLQ_DROP",
    name: "D7b - Format DLQ Drop",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [520, 1420]
  }
];

// Add nodes
for (const node of newNodes) {
  // Check if node with this name already exists
  const exists = wf.nodes.find(n => n.name === node.name);
  if (!exists) {
    wf.nodes.push(node);
    console.log(`Added node: ${node.name}`);
  } else {
    console.log(`Node already exists: ${node.name}`);
  }
}

// New connections to add
const newConnections = {
  // From A5 - Parse Intent to new D* nodes
  "A5 - Parse Intent": {
    main: [
      // Existing connections will be preserved, we need to add new ones
      { node: "D1 - Is STATUS?", type: "main", index: 0 },
      { node: "D2 - Is FLAGS_LIST?", type: "main", index: 0 },
      { node: "D3 - Is FLAGS_SET?", type: "main", index: 0 },
      { node: "D4 - Is DLQ_LIST?", type: "main", index: 0 },
      { node: "D5 - Is DLQ_SHOW?", type: "main", index: 0 },
      { node: "D6 - Is DLQ_REPLAY?", type: "main", index: 0 },
      { node: "D7 - Is DLQ_DROP?", type: "main", index: 0 }
    ]
  },
  // D1 chain
  "D1 - Is STATUS?": { main: [[{ node: "D1a - Get Status (DB)", type: "main", index: 0 }], []] },
  "D1a - Get Status (DB)": { main: [[{ node: "D1b - Format Status", type: "main", index: 0 }]] },
  "D1b - Format Status": { main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]] },
  // D2 chain
  "D2 - Is FLAGS_LIST?": { main: [[{ node: "D2a - Get Flags (DB)", type: "main", index: 0 }], []] },
  "D2a - Get Flags (DB)": { main: [[{ node: "D2b - Format Flags List", type: "main", index: 0 }]] },
  "D2b - Format Flags List": { main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]] },
  // D3 chain
  "D3 - Is FLAGS_SET?": { main: [[{ node: "D3a - Set Flag (DB)", type: "main", index: 0 }], []] },
  "D3a - Set Flag (DB)": { main: [[{ node: "D3b - Format Flag Set", type: "main", index: 0 }]] },
  "D3b - Format Flag Set": { main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]] },
  // D4 chain
  "D4 - Is DLQ_LIST?": { main: [[{ node: "D4a - Get DLQ List (DB)", type: "main", index: 0 }], []] },
  "D4a - Get DLQ List (DB)": { main: [[{ node: "D4b - Format DLQ List", type: "main", index: 0 }]] },
  "D4b - Format DLQ List": { main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]] },
  // D5 chain
  "D5 - Is DLQ_SHOW?": { main: [[{ node: "D5a - Get DLQ Item (DB)", type: "main", index: 0 }], []] },
  "D5a - Get DLQ Item (DB)": { main: [[{ node: "D5b - Format DLQ Show", type: "main", index: 0 }]] },
  "D5b - Format DLQ Show": { main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]] },
  // D6 chain
  "D6 - Is DLQ_REPLAY?": { main: [[{ node: "D6a - Replay DLQ (DB)", type: "main", index: 0 }], []] },
  "D6a - Replay DLQ (DB)": { main: [[{ node: "D6b - Format DLQ Replay", type: "main", index: 0 }]] },
  "D6b - Format DLQ Replay": { main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]] },
  // D7 chain
  "D7 - Is DLQ_DROP?": { main: [[{ node: "D7a - Drop DLQ (DB)", type: "main", index: 0 }], []] },
  "D7a - Drop DLQ (DB)": { main: [[{ node: "D7b - Format DLQ Drop", type: "main", index: 0 }]] },
  "D7b - Format DLQ Drop": { main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]] }
};

// Merge connections
// For A5 - Parse Intent, we need to add to existing array
if (wf.connections["A5 - Parse Intent"]) {
  const existing = wf.connections["A5 - Parse Intent"].main[0] || [];
  const toAdd = newConnections["A5 - Parse Intent"].main;
  for (const conn of toAdd) {
    const alreadyExists = existing.find(c => c.node === conn.node);
    if (!alreadyExists) {
      existing.push(conn);
      console.log(`Added connection: A5 -> ${conn.node}`);
    }
  }
  wf.connections["A5 - Parse Intent"].main[0] = existing;
}

// Add all other connections
for (const [from, conn] of Object.entries(newConnections)) {
  if (from === "A5 - Parse Intent") continue; // Already handled
  if (!wf.connections[from]) {
    wf.connections[from] = conn;
    console.log(`Added connections for: ${from}`);
  }
}

// Write updated workflow
fs.writeFileSync(W14_PATH, JSON.stringify(wf, null, 2));
console.log('\n✅ W14 patched successfully with P2-02 command handlers');
