const fs = require('fs');
const targetFile = 'c:/Users/mon pc/Desktop/ralphé_final_patch/project/workflows/W4.2_CART_MANAGER.json';
let w = JSON.parse(fs.readFileSync(targetFile, 'utf8'));

// 1. Cloud Print Trigger
const printTrigger = {
    "parameters": {
        "url": "={{ $env.N8N_WEBHOOK_URL || 'http://n8n:5678' }}/webhook/kitchen-print",
        "method": "POST",
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ order_id: $json.state?.lastOrderId || $json.debug?.orderId || $json.order_id || $json.orderid || $node['C9 - Create Order (DB)'].json.order_id }) }}",
        "options": {
            "timeout": 3000
        }
    },
    "id": "CLOUD_PRINT_TRIGGER",
    "name": "Trigger Cloud Print",
    "type": "n8n-nodes-base.httpRequest",
    "typeVersion": 4,
    "position": [460, -480],
    "continueOnFail": true
};

// 2. KDS Realtime Trigger (Supabase REST or webhook)
const kdsTrigger = {
    "parameters": {
        "url": "={{ $env.SUPABASE_URL || 'http://supabase:8000' }}/rest/v1/kds_tickets",
        "method": "POST",
        "sendHeaders": true,
        "headerParameters": {
            "parameters": [
                { "name": "apikey", "value": "={{ $env.SUPABASE_ANON_KEY }}" },
                { "name": "Authorization", "value": "Bearer {{ $env.SUPABASE_ANON_KEY }}" },
                { "name": "Content-Type", "value": "application/json" },
                { "name": "Prefer", "value": "return=minimal" }
            ]
        },
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ order_id: $node['C9 - Create Order (DB)'].json.order_id, status: 'PENDING', payload: $node['C9 - Create Order (DB)'].json.summary, total_cents: $node['C9 - Create Order (DB)'].json.total_cents }) }}",
        "options": {
            "timeout": 3000
        }
    },
    "id": "KDS_SYNC_TRIGGER",
    "name": "Sync to KDS (Supabase)",
    "type": "n8n-nodes-base.httpRequest",
    "typeVersion": 4,
    "position": [460, -660],
    "continueOnFail": true
};

const c9Index = w.nodes.findIndex(n => n.name === 'C9 - Create Order (DB)');
if (c9Index > -1) {
    w.nodes.push(printTrigger, kdsTrigger);
    const connections = w.connections['C9 - Create Order (DB)']?.main[0] || [];
    connections.push({ node: "Trigger Cloud Print", type: "main", index: 0 });
    connections.push({ node: "Sync to KDS (Supabase)", type: "main", index: 0 });
    w.connections['C9 - Create Order (DB)'].main[0] = connections;
}

fs.writeFileSync(targetFile, JSON.stringify(w, null, 2));
console.log('Successfully patched W4.2 for Cloud Print & KDS!');
