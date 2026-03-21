#!/usr/bin/env node
/**
 * P2-04: Patch W14 to add STATS command handler
 */
const fs = require('fs');
const path = require('path');

const W14_PATH = path.join(__dirname, '..', 'workflows', 'W14_ADMIN_WA_SUPPORT_CONSOLE.json');

const wf = JSON.parse(fs.readFileSync(W14_PATH, 'utf8'));

// 1. Update A5 - Parse Intent to handle STATS command
const a5Node = wf.nodes.find(n => n.name === 'A5 - Parse Intent');
if (a5Node) {
  const jsCode = a5Node.parameters.jsCode;

  // Check if STATS is already handled
  if (!jsCode.includes("'stats'")) {
    // Find the line "else action = 'UNKNOWN';" and insert STATS handling before it
    const updatedCode = jsCode.replace(
      /else action = 'UNKNOWN';/,
      `// P2-04: STATS command
else if (cmd === 'stats') {
  action = 'STATS';
  const sub = (args[0] || 'today').toLowerCase();
  e.adminStatsRange = sub;
  if (sub === 'week' || sub === '7d') {
    e.adminStatsDays = 7;
  } else if (sub === 'month' || sub === '30d') {
    e.adminStatsDays = 30;
  } else {
    e.adminStatsDays = 1;
  }
}

else action = 'UNKNOWN';`
    );
    a5Node.parameters.jsCode = updatedCode;
    console.log('Updated A5 - Parse Intent to handle STATS command');
  } else {
    console.log('A5 - Parse Intent already handles STATS command');
  }
}

// 2. Add new nodes for STATS command
const newNodes = [
  {
    parameters: {
      conditions: {
        string: [{ value1: "={{$json.adminAction}}", operation: "equal", value2: "STATS" }]
      }
    },
    id: "D8_IS_STATS",
    name: "D8 - Is STATS?",
    type: "n8n-nodes-base.if",
    typeVersion: 2,
    position: [120, 1540]
  },
  {
    parameters: {
      operation: "executeQuery",
      query: "SELECT get_daily_stats(CURRENT_DATE) AS stats;",
      additionalFields: {}
    },
    id: "D8A_STATS_DB",
    name: "D8a - Get Stats (DB)",
    type: "n8n-nodes-base.postgres",
    typeVersion: 2,
    position: [320, 1540]
  },
  {
    parameters: {
      language: "javascript",
      jsCode: `const e = $json;
const statsData = e.data?.[0]?.stats || {};
const date = statsData.date || new Date().toISOString().slice(0, 10);
const inbound = statsData.inbound || {};
const outbound = statsData.outbound || {};
const errors = statsData.errors || {};
const latency = statsData.latency || {};

let txt = '*Daily Stats (' + date + ')*\\n';
txt += '═══════════════════════\\n\\n';

txt += '*Inbound Messages*\\n';
txt += '  Total: ' + (inbound.total || 0) + '\\n';
txt += '  WhatsApp: ' + (inbound.whatsapp || 0) + '\\n';
txt += '  Instagram: ' + (inbound.instagram || 0) + '\\n';
txt += '  Messenger: ' + (inbound.messenger || 0) + '\\n\\n';

txt += '*Outbound Messages*\\n';
txt += '  Total: ' + (outbound.total || 0) + '\\n';
txt += '  WhatsApp: ' + (outbound.whatsapp || 0) + '\\n';
txt += '  Instagram: ' + (outbound.instagram || 0) + '\\n';
txt += '  Messenger: ' + (outbound.messenger || 0) + '\\n\\n';

txt += '*Errors*\\n';
txt += '  Total: ' + (errors.total || 0) + '\\n';
txt += '  Auth: ' + (errors.auth || 0) + '\\n';
txt += '  Validation: ' + (errors.validation || 0) + '\\n';
txt += '  Outbound: ' + (errors.outbound || 0) + '\\n\\n';

if (latency && latency.samples > 0) {
  txt += '*Latency*\\n';
  txt += '  Samples: ' + latency.samples + '\\n';
  txt += '  Avg: ' + (latency.avg_ms || 0) + 'ms\\n';
  txt += '  P50: ' + (latency.p50_ms || 0) + 'ms\\n';
  txt += '  P95: ' + (latency.p95_ms || 0) + 'ms\\n';
  txt += '  P99: ' + (latency.p99_ms || 0) + 'ms\\n';
  txt += '  Max: ' + (latency.max_ms || 0) + 'ms\\n';
} else {
  txt += '*Latency*\\n  No samples yet\\n';
}

txt += '\\n➡️ !stats [today|week|month]';

return [{json:{...e, adminReplyText: txt.trim()}}];`
    },
    id: "D8B_FORMAT_STATS",
    name: "D8b - Format Stats",
    type: "n8n-nodes-base.code",
    typeVersion: 2,
    position: [520, 1540]
  }
];

// Add nodes
for (const node of newNodes) {
  const exists = wf.nodes.find(n => n.name === node.name);
  if (!exists) {
    wf.nodes.push(node);
    console.log(`Added node: ${node.name}`);
  } else {
    console.log(`Node already exists: ${node.name}`);
  }
}

// 3. Add connections
// Add D8 - Is STATS? to A5 - Parse Intent outputs
if (wf.connections["A5 - Parse Intent"]) {
  const existing = wf.connections["A5 - Parse Intent"].main[0] || [];
  const statsConn = { node: "D8 - Is STATS?", type: "main", index: 0 };
  const alreadyExists = existing.find(c => c.node === "D8 - Is STATS?");
  if (!alreadyExists) {
    existing.push(statsConn);
    wf.connections["A5 - Parse Intent"].main[0] = existing;
    console.log('Added connection: A5 -> D8 - Is STATS?');
  }
}

// Add D8 chain connections
const newConnections = {
  "D8 - Is STATS?": { main: [[{ node: "D8a - Get Stats (DB)", type: "main", index: 0 }], []] },
  "D8a - Get Stats (DB)": { main: [[{ node: "D8b - Format Stats", type: "main", index: 0 }]] },
  "D8b - Format Stats": { main: [[{ node: "O0 - Build Admin Outbox", type: "main", index: 0 }]] }
};

for (const [from, conn] of Object.entries(newConnections)) {
  if (!wf.connections[from]) {
    wf.connections[from] = conn;
    console.log(`Added connections for: ${from}`);
  }
}

// Write updated workflow
fs.writeFileSync(W14_PATH, JSON.stringify(wf, null, 2));
console.log('\n✅ W14 patched successfully with P2-04 STATS command handler');
