const fs = require('fs');
const path = require('path');

const srcPath = 'c:/Users/mon pc/Desktop/ralphé_final_patch/project/workflows/W4_CORE.json';
const w4 = JSON.parse(fs.readFileSync(srcPath, 'utf8'));

const nodesByMap = new Map();
w4.nodes.forEach(n => nodesByMap.set(n.name, n));

function extractSection(name, nodeNames, startNodeName) {
    const nodes = [];
    const connections = {};

    // Re-map trigger
    const trigger = {
        "parameters": {},
        "id": "trigger-" + Math.random().toString(36).substring(7),
        "name": "Execute Workflow Trigger",
        "type": "n8n-nodes-base.executeWorkflowTrigger",
        "typeVersion": 1,
        "position": [0, 0]
    };
    nodes.push(trigger);

    if (startNodeName) {
        connections["Execute Workflow Trigger"] = {
            main: [
                [{ node: startNodeName, type: "main", index: 0 }]
            ]
        };
    }

    nodeNames.forEach(nName => {
        if (nodesByMap.has(nName)) {
            nodes.push(nodesByMap.get(nName));
        }
        if (w4.connections[nName]) {
            // filtering out connections to nodes outside this section
            const validConns = [[], []];
            let hasValid = false;
            const originalConns = w4.connections[nName].main;
            if (Array.isArray(originalConns)) {
                originalConns.forEach((branch, idx) => {
                    if (Array.isArray(branch)) {
                        branch.forEach(target => {
                            if (nodeNames.includes(target.node)) {
                                validConns[idx] = validConns[idx] || [];
                                validConns[idx].push(target);
                                hasValid = true;
                            }
                        });
                    }
                });
            }
            if (hasValid) {
                connections[nName] = { main: validConns.filter(b => b.length > 0) };
            }
        }
    });

    return {
        "name": name,
        "active": false,
        "settings": { ...w4.settings },
        "nodes": nodes,
        "connections": connections
    };
}

// Extract Cart Manager (W4.2)
const cartNodes = [
    "C7 - Save State+Cart (DB)",
    "C8 - Action CHECKOUT?",
    "C8A - Action DELIVERY_QUOTE?",
    "C8B - Action ADDRESS_AMBIGUOUS?",
    "DQ1 - Delivery Quote (DB)",
    "DQ2 - Slots enabled?",
    "DQ3 - List Slots (DB)",
    "DQ4 - Build Delivery Quote Response",
    "DQ5 - Save State (DB)",
    "CA1 - Upsert Clarification (DB)",
    "CA2 - Log ADDRESS_AMBIGUOUS (DB)",
    "C9 - Create Order (DB)",
    "C10 - Build Order Response",
    "Trigger Inventory Sync",
    "Track Order Confirmed",
    "Trigger Upsell Engine",
    "C11 - Finalize Response (default)",
    "C12 - Enqueue Outbox (P0)",
    "C12b - Outbox Enqueue (DB)",
    "C12c - Outbox Result"
];
const w4_2 = extractSection("W4.2 - CART & ORDER MANAGER", cartNodes, "C7 - Save State+Cart (DB)");

// Extract FAQ Agent (W4.3)
const faqNodes = [
    "S0 - Is FAQ Query?",
    "S1 - Search FAQ (DB)",
    "S2 - Apply FAQ Result",
    "Sx - PassThrough",
    "S4 - Is Support Handoff?",
    "S5 - Upsert Ticket (DB)",
    "S6 - Log Ticket Message (DB)",
    "S7 - Ensure Support Reply"
];
const w4_3 = extractSection("W4.3 - FAQ & SUPPORT AGENT", faqNodes, "S0 - Is FAQ Query?");

// Create Router (W4.1)
// The router keeps C0 to C6, plus Menus caching, STT, etc.
const routerNodeNames = [
    "IN - From Adapters",
    "C0 - Validate Event",
    "C1 - Load State+Cart (DB)",
    "C2 - Merge State Defaults",
    "C3 - Voice STT (optional)",
    "C3x - AudioUrl Blocked?",
    "C3y - Log SSRF Block (DB)",
    "C3b - Menu Cache Get",
    "C3c - Menu Cache Hit?",
    "C4 - Load Menu Index (DB)",
    "C4b - Menu Cache Set",
    "C5 - Build Menu Maps",
    "C6 - Router (safe, LLM optional)"
];

const w4_1_nodes = routerNodeNames.map(name => nodesByMap.get(name)).filter(Boolean);
const w4_1_conns = {};
routerNodeNames.forEach(name => {
    if (w4.connections[name]) {
        // only keep connections within the router
        const validConns = [[], []];
        let hasValid = false;
        const originalConns = w4.connections[name].main;
        if (Array.isArray(originalConns)) {
            originalConns.forEach((branch, idx) => {
                if (Array.isArray(branch)) {
                    branch.forEach(target => {
                        if (routerNodeNames.includes(target.node)) {
                            validConns[idx] = validConns[idx] || [];
                            validConns[idx].push(target);
                            hasValid = true;
                        }
                    });
                }
            });
        }
        if (hasValid) {
            w4_1_conns[name] = { main: validConns.filter(b => b.length > 0) };
        }
    }
});

// Add the Intent Switcher and execution nodes
w4_1_nodes.push({
    "parameters": {
        "dataType": "string",
        "value1": "={{$json.intent}}",
        "rules": {
            "rules": [
                {
                    "id": "faq_rule",
                    "value2": "FAQ_QUERY",
                    "output": 0
                },
                {
                    "id": "support_rule",
                    "value2": "HANDOFF_SUPPORT",
                    "output": 0
                },
                {
                    "id": "support_del_rule",
                    "value2": "DELIVERY_HANDOFF",
                    "output": 0
                },
                {
                    "id": "cart1",
                    "value2": "CART_UPDATED",
                    "output": 1
                },
                {
                    "id": "cart2",
                    "value2": "CONFIRM",
                    "output": 1
                },
                {
                    "id": "cart3",
                    "value2": "CHECKOUT",
                    "output": 1
                },
                {
                    "id": "cart4",
                    "value2": "DELIVERY_ADDRESS",
                    "output": 1
                },
                {
                    "id": "cart5",
                    "value2": "DELIVERY_QUOTE",
                    "output": 1
                },
                {
                    "id": "cart6",
                    "value2": "SLOT_OK",
                    "output": 1
                }
            ]
        },
        "fallbackOutput": 2
    },
    "id": "switch-intent",
    "name": "Switch Intent",
    "type": "n8n-nodes-base.switch",
    "typeVersion": 1,
    "position": [100, 0]
});

w4_1_conns["C6 - Router (safe, LLM optional)"] = {
    main: [
        [{ node: "Switch Intent", type: "main", index: 0 }]
    ]
};

// Add Execute W4.2
w4_1_nodes.push({
    "parameters": {
        "workflowId": "W4.2_CART_MANAGER",
        "options": { "waitTillFinished": true }
    },
    "id": "exec-cart",
    "name": "Call CART_MANAGER",
    "type": "n8n-nodes-base.executeWorkflow",
    "typeVersion": 1,
    "position": [400, 100]
});

// Add Execute W4.3
w4_1_nodes.push({
    "parameters": {
        "workflowId": "W4.3_FAQ_AGENT",
        "options": { "waitTillFinished": true }
    },
    "id": "exec-faq",
    "name": "Call FAQ_AGENT",
    "type": "n8n-nodes-base.executeWorkflow",
    "typeVersion": 1,
    "position": [400, -100]
});

// For the fallback (other intents like LANG_SET, SHOW_MENU), we need to save state and send to outbox.
// We can just add C7, C11, C12 directly in W4.1 for the simple logic, or pass it to CART_MANAGER.
// Let's pass the fallback to CART_MANAGER to handle C7+C11+C12 as a unified exit.
// Or we just duplicate C7+C11+C12 in W4.1 for the Router's own responses.
// Since CART_MANAGER already has C7 -> C11 -> C12, the simplest is to send the fallback to CART_MANAGER too, 
// and let CART_MANAGER skip checkout logic for simple intents.
// Let's modify CART_MANAGER to accept all standard responses, OR we just build an orchestrator in W4.1.
// Let's just create C7, C11, C12 in W4.1 specifically for immediate responses.

const simpleResponseNodes = [
    "C7 - Save State+Cart (DB)",
    "C11 - Finalize Response (default)",
    "C12 - Enqueue Outbox (P0)",
    "C12b - Outbox Enqueue (DB)",
    "C12c - Outbox Result"
];
simpleResponseNodes.forEach(n => {
    const original = nodesByMap.get(n);
    if (original) w4_1_nodes.push(JSON.parse(JSON.stringify(original)));
});

// Logic:
// FAQ -> W4.3, which MUST return back. Then W4.1 executes C7, C11, C12.
// Cart -> W4.2, which internally DOES C7, C11, C12 (Wait, W4.2 DOES IT).
// Actually, W4.2 does everything. If we just let W4.2 and W4.3 do their specific DB/Outbox enqueuing, we don't need it in W4.1.
// But wait, W4.3 doesn't have C7/C11/C12 right now, it relies on them being attached later in W4_CORE.
// In original W4_CORE: FAQ -> S7 -> C7 -> ...
// Let's just bundle S7 -> C7 -> C11 -> C12 inside W4.3.
// Let's use string manipulation for simplicity and power.

w4_1_conns["Switch Intent"] = {
    main: [
        [{ node: "Call FAQ_AGENT", type: "main", index: 0 }],
        [{ node: "Call CART_MANAGER", type: "main", index: 0 }],
        [{ node: "C7 - Save State+Cart (DB)", type: "main", index: 0 }]
    ]
};

// Wire fallback logic inside W4.1
w4_1_conns["C7 - Save State+Cart (DB)"] = { main: [[{ node: "C11 - Finalize Response (default)", type: "main", index: 0 }]] };
w4_1_conns["C11 - Finalize Response (default)"] = { main: [[{ node: "C12 - Enqueue Outbox (P0)", type: "main", index: 0 }]] };
w4_1_conns["C12 - Enqueue Outbox (P0)"] = { main: [[{ node: "C12b - Outbox Enqueue (DB)", type: "main", index: 0 }]] };
w4_1_conns["C12b - Outbox Enqueue (DB)"] = { main: [[{ node: "C12c - Outbox Result", type: "main", index: 0 }]] };

const w4_1 = {
    "name": "W4.1 - ROUTER (State + Voice)",
    "active": false,
    "settings": { ...w4.settings },
    "nodes": w4_1_nodes,
    "connections": w4_1_conns
};

// Write files
fs.writeFileSync('c:/Users/mon pc/Desktop/ralphé_final_patch/project/workflows/W4.1_ROUTER.json', JSON.stringify(w4_1, null, 2));
fs.writeFileSync('c:/Users/mon pc/Desktop/ralphé_final_patch/project/workflows/W4.2_CART_MANAGER.json', JSON.stringify(w4_2, null, 2));
fs.writeFileSync('c:/Users/mon pc/Desktop/ralphé_final_patch/project/workflows/W4.3_FAQ_AGENT.json', JSON.stringify(w4_3, null, 2));

console.log("Successfully split W4_CORE into Micro-Services.");
