const fs = require('fs');
const path = require('path');

const targetFile = 'c:/Users/mon pc/Desktop/ralphé_final_patch/project/workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json';
let w14 = JSON.parse(fs.readFileSync(targetFile, 'utf8'));

// 1. Update A5 - Parse Intent
const a5Node = w14.nodes.find(n => n.name === 'A5 - Parse Intent');
let a5Code = a5Node.parameters.jsCode;

const newUsage = `
    '*Catalogue (Strapi)*',
    '- !menu stock <code_produit> <quantité>',
    '- !menu 86 <code_produit> (rupture)',
    '- !menu list',
`;
a5Code = a5Code.replace(/    '\*Delivery Zones\*',/, newUsage + `\n    '*Delivery Zones*',`);

const newCommands = `
// STRAPI MENU
else if (cmd === 'menu' || cmd === 'product' || cmd === 'produit') {
  const sub = (args[0] || 'list').toLowerCase();
  e.adminStrapiOp = sub;
  if (sub === '86' || sub === 'out' || sub === 'rupture') {
    action = 'STRAPI_PRODUCT_86';
    e.adminStrapiProduct = (args[1] || '').toString().toUpperCase();
    e.adminStrapiStock = 0;
  } else if (sub === 'stock') {
    action = 'STRAPI_PRODUCT_STOCK';
    e.adminStrapiProduct = (args[1] || '').toString().toUpperCase();
    e.adminStrapiStock = parseInt(args[2] || '0', 10);
  } else if (sub === 'list' || sub === 'ls') {
    action = 'STRAPI_PRODUCT_LIST';
  } else {
    action = 'UNKNOWN';
  }
}
`;
a5Code = a5Code.replace(/\/\/ P2-DZ-01: ORDER command/, newCommands + '\n// P2-DZ-01: ORDER command');

if (a5Code.indexOf('STRAPI_PRODUCT_86') === -1) {
    console.error("Failed to inject Strapi commands");
    process.exit(1);
}
a5Node.parameters.jsCode = a5Code;

// Update output properties
a5Code = a5Code.replace(/adminZoneActive: zoneActive\n\}\}\];/, `adminZoneActive: zoneActive,
  adminStrapiOp: e.adminStrapiOp,
  adminStrapiProduct: e.adminStrapiProduct,
  adminStrapiStock: e.adminStrapiStock
}}];`);
a5Node.parameters.jsCode = a5Code;

const nodesToAdd = [];
const connectionsToAdd = {
    "A5 - Parse Intent": {
        "main": [
            [
                // We will add to B6 - Is UNKNOWN? connections later
            ]
        ]
    }
};

// 2. Add New Nodes for STRAPI_PRODUCT_86 & STRAPI_PRODUCT_STOCK
const S1_IF = {
    "parameters": {
        "conditions": {
            "boolean": [
                {
                    "value1": "={{['STRAPI_PRODUCT_86', 'STRAPI_PRODUCT_STOCK'].includes($json.adminAction)}}",
                    "operation": "isTrue"
                }
            ]
        }
    },
    "id": "S1_IF_STRAPI_STOCK",
    "name": "S1 - Is STRAPI STOCK/86?",
    "type": "n8n-nodes-base.if",
    "typeVersion": 2,
    "position": [860, 1500]
};

const S2_GET = {
    "parameters": {
        "url": "={{ $env.STRAPI_URL || 'http://strapi:1337' }}/api/products?filters[code][$eq]={{$json.adminStrapiProduct}}",
        "sendHeaders": true,
        "headerParameters": {
            "parameters": [
                {
                    "name": "Authorization",
                    "value": "Bearer {{ $env.STRAPI_API_TOKEN }}"
                }
            ]
        },
        "options": {}
    },
    "id": "S2_GET_PRODUCT",
    "name": "S2 - GET Product (Strapi)",
    "type": "n8n-nodes-base.httpRequest",
    "typeVersion": 3,
    "position": [1090, 1500]
};

const S3_IF = {
    "parameters": {
        "conditions": {
            "number": [
                {
                    "value1": "={{$json.data && $json.data.length ? 1 : 0}}",
                    "operation": "larger",
                    "value2": 0
                }
            ]
        }
    },
    "id": "S3_IF_FOUND",
    "name": "S3 - Is Product Found?",
    "type": "n8n-nodes-base.if",
    "typeVersion": 2,
    "position": [1310, 1500]
};

const S4_PUT = {
    "parameters": {
        "method": "PUT",
        "url": "={{ $env.STRAPI_URL || 'http://strapi:1337' }}/api/products/{{ $json.data[0].id }}",
        "sendHeaders": true,
        "headerParameters": {
            "parameters": [
                {
                    "name": "Authorization",
                    "value": "Bearer {{ $env.STRAPI_API_TOKEN }}"
                }
            ]
        },
        "sendBody": true,
        "bodyParameters": {
            "parameters": [
                {
                    "name": "data",
                    "value": "={{ { stock_quantity: $node['A5 - Parse Intent'].json.adminStrapiStock } }}"
                }
            ]
        },
        "options": {}
    },
    "id": "S4_PUT_PRODUCT",
    "name": "S4 - PUT Product Stock (Strapi)",
    "type": "n8n-nodes-base.httpRequest",
    "typeVersion": 3,
    "position": [1510, 1480]
};

const S5_FMT_OK = {
    "parameters": {
        "jsCode": "const e = $('A5 - Parse Intent').item.json;\nconst p = $node['S2 - GET Product (Strapi)'].json.data[0];\nconst newStock = e.adminStrapiStock;\nconst loc = (e.adminConsole?.locale || 'fr');\n\ne.adminReplyText = (loc === 'ar') \n  ? `✅ تم التحديث بنउचर!\\nالمنتج: ${p.attributes.name} (${e.adminStrapiProduct})\\nالمخزون الجديد: ${newStock}`\n  : `✅ Produit mis à jour !\\nProduit: ${p.attributes.name} (${e.adminStrapiProduct})\\nNouveau stock: ${newStock}`;\n\nreturn [{json:e}];"
    },
    "id": "S5_FMT_OK",
    "name": "S5 - Format OK",
    "type": "n8n-nodes-base.code",
    "typeVersion": 2,
    "position": [1710, 1480]
};

const S6_FMT_ERR = {
    "parameters": {
        "jsCode": "const e = $('A5 - Parse Intent').item.json;\nconst loc = (e.adminConsole?.locale || 'fr');\ne.adminReplyText = (loc === 'ar') \n  ? `❌ لم يتم العثور على المنتج بالكود: ${e.adminStrapiProduct}`\n  : `❌ Produit introuvable pour le code: ${e.adminStrapiProduct}`;\nreturn [{json:e}];"
    },
    "id": "S6_FMT_ERR",
    "name": "S6 - Format Error",
    "type": "n8n-nodes-base.code",
    "typeVersion": 2,
    "position": [1510, 1680]
};

// STRAPI_PRODUCT_LIST
const SL1_IF = {
    "parameters": {
        "conditions": {
            "boolean": [
                {
                    "value1": "={{$json.adminAction === 'STRAPI_PRODUCT_LIST'}}",
                    "operation": "isTrue"
                }
            ]
        }
    },
    "id": "SL1_IF_STRAPI_LIST",
    "name": "SL1 - Is STRAPI LIST?",
    "type": "n8n-nodes-base.if",
    "typeVersion": 2,
    "position": [860, 1680]
};

const SL2_GET = {
    "parameters": {
        "url": "={{ $env.STRAPI_URL || 'http://strapi:1337' }}/api/products?pagination[limit]=50&sort=stock_quantity:asc",
        "sendHeaders": true,
        "headerParameters": {
            "parameters": [
                {
                    "name": "Authorization",
                    "value": "Bearer {{ $env.STRAPI_API_TOKEN }}"
                }
            ]
        },
        "options": {}
    },
    "id": "SL2_GET_LIST",
    "name": "SL2 - GET Products (Strapi)",
    "type": "n8n-nodes-base.httpRequest",
    "typeVersion": 3,
    "position": [1090, 1680]
};

const SL3_FMT = {
    "parameters": {
        "jsCode": "const e = $('A5 - Parse Intent').item.json;\nconst prods = $json.data || [];\nconst loc = (e.adminConsole?.locale || 'fr');\n\nlet txt = (loc === 'ar') ? '📦 المخزون (أقل 50):\\n' : '📦 Stock (top 50 faibles):\\n';\nfor (const p of prods) {\n  const a = p.attributes;\n  const stock = a.stock_quantity || 0;\n  const stStr = stock <= 0 ? '⛔ RUPTURE' : (stock <= 5 ? `⚠️ ${stock}` : `✅ ${stock}`);\n  txt += `- ${a.code} | ${a.name}: ${stStr}\\n`;\n}\nif (!prods.length) txt = '❌ Aucun produit.';\ne.adminReplyText = txt;\nreturn [{json:e}];"
    },
    "id": "SL3_FMT",
    "name": "SL3 - Format List",
    "type": "n8n-nodes-base.code",
    "typeVersion": 2,
    "position": [1310, 1680]
};

nodesToAdd.push(S1_IF, S2_GET, S3_IF, S4_PUT, S5_FMT_OK, S6_FMT_ERR, SL1_IF, SL2_GET, SL3_FMT);

// Connections
if (!w14.connections['A5 - Parse Intent']) w14.connections['A5 - Parse Intent'] = { main: [[]] };
const a5Targets = w14.connections['A5 - Parse Intent'].main[0];
a5Targets.push({ "node": "S1 - Is STRAPI STOCK/86?", "type": "main", "index": 0 });
a5Targets.push({ "node": "SL1 - Is STRAPI LIST?", "type": "main", "index": 0 });

w14.connections["S1 - Is STRAPI STOCK/86?"] = {
    main: [
        [{ node: "S2 - GET Product (Strapi)", type: "main", index: 0 }],
        []
    ]
};
w14.connections["S2 - GET Product (Strapi)"] = {
    main: [[{ node: "S3 - Is Product Found?", type: "main", index: 0 }]]
};
w14.connections["S3 - Is Product Found?"] = {
    main: [
        [{ node: "S4 - PUT Product Stock (Strapi)", type: "main", index: 0 }],
        [{ node: "S6 - Format Error", type: "main", index: 0 }]
    ]
};
w14.connections["S4 - PUT Product Stock (Strapi)"] = {
    main: [[{ node: "S5 - Format OK", type: "main", index: 0 }]]
};

w14.connections["SL1 - Is STRAPI LIST?"] = {
    main: [
        [{ node: "SL2 - GET Products (Strapi)", type: "main", index: 0 }],
        []
    ]
};
w14.connections["SL2 - GET Products (Strapi)"] = {
    main: [[{ node: "SL3 - Format List", type: "main", index: 0 }]]
};

// Wire the formatted outputs to O0 - Build Admin Outbox
if (!w14.connections["S5 - Format OK"]) w14.connections["S5 - Format OK"] = { main: [[]] };
w14.connections["S5 - Format OK"].main[0].push({ node: "O0 - Build Admin Outbox", type: "main", index: 0 });

if (!w14.connections["S6 - Format Error"]) w14.connections["S6 - Format Error"] = { main: [[]] };
w14.connections["S6 - Format Error"].main[0].push({ node: "O0 - Build Admin Outbox", type: "main", index: 0 });

if (!w14.connections["SL3 - Format List"]) w14.connections["SL3 - Format List"] = { main: [[]] };
w14.connections["SL3 - Format List"].main[0].push({ node: "O0 - Build Admin Outbox", type: "main", index: 0 });

w14.nodes.push(...nodesToAdd);

fs.writeFileSync(targetFile, JSON.stringify(w14, null, 2));
console.log('Successfully patched W14_ADMIN_WA_SUPPORT_CONSOLE.json!');
