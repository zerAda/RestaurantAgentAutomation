const fs = require('fs');

const targetFile = 'c:/Users/mon pc/Desktop/ralphé_final_patch/project/workflows/W4.1_ROUTER.json';
let w = JSON.parse(fs.readFileSync(targetFile, 'utf8'));

const IF_SYNC = {
    "parameters": {
        "conditions": {
            "boolean": [
                {
                    "value1": "={{$json.l10nPersistLocale === true}}",
                    "operation": "isTrue"
                }
            ]
        }
    },
    "id": "C14_IF_SYNC_DIALECT",
    "name": "C14 - Should Sync Dialect?",
    "type": "n8n-nodes-base.if",
    "typeVersion": 2,
    "position": [1660, 420]
};

const EXEC_SYNC = {
    "parameters": {
        "workflowId": "W56 - Strapi Dialect Sync",
        "mode": "fireAndForget",
        "workflowInputs": {
            "mappingMode": "defineBelow",
            "value": {},
            "values": [
                {
                    "name": "phone",
                    "value": "={{$json.userId}}"
                },
                {
                    "name": "locale",
                    "value": "={{$json.state?.localePref || $json.state?.locale}}"
                }
            ]
        },
        "options": {
            "waitTillFinished": false
        }
    },
    "id": "C15_EXEC_SYNC_DIALECT",
    "name": "C15 - Execute Dialect Sync",
    "type": "n8n-nodes-base.executeWorkflow",
    "typeVersion": 1,
    "position": [1880, 400]
};

w.nodes.push(IF_SYNC, EXEC_SYNC);

// Connect C12c to C14
if (!w.connections['C12c - Outbox Result']) {
    w.connections['C12c - Outbox Result'] = { main: [[]] };
}
w.connections['C12c - Outbox Result'].main[0].push({
    node: "C14 - Should Sync Dialect?",
    type: "main",
    index: 0
});

// Connect C14 to C15
w.connections['C14 - Should Sync Dialect?'] = {
    main: [
        [
            {
                node: "C15 - Execute Dialect Sync",
                type: "main",
                index: 0
            }
        ],
        []
    ]
};

fs.writeFileSync(targetFile, JSON.stringify(w, null, 2));
console.log('Successfully patched W4.1 for Dialect Sync!');
