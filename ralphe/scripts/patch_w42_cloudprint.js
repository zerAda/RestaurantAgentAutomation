const fs = require('fs');
const targetFile = 'c:/Users/mon pc/Desktop/ralphé_final_patch/project/workflows/W4.2_CART_MANAGER.json';
let w = JSON.parse(fs.readFileSync(targetFile, 'utf8'));

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

w.nodes.push(printTrigger);

if (!w.connections['C9 - Create Order (DB)']) w.connections['C9 - Create Order (DB)'] = { main: [[]] };
w.connections['C9 - Create Order (DB)'].main[0].push({
    "node": "Trigger Cloud Print",
    "type": "main",
    "index": 0
});

fs.writeFileSync(targetFile, JSON.stringify(w, null, 2));
console.log('Successfully patched W4.2 for Cloud Print!');
