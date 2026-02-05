const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, '../workflows/W4_CORE.json');
const raw = fs.readFileSync(filePath, 'utf8');
const workflow = JSON.parse(raw);

// Find C6 Router node
const node = workflow.nodes.find(n => n.name === 'C6 - Router (safe, LLM optional)');
if (!node) {
    console.error('Node C6 not found');
    process.exit(1);
}

let code = node.parameters.jsCode;

// Patcher 1: Menu Image
const menuLogicSig = `if (normalizedLower === 'menu' || text === 'HELP_MENU' || lower === 'menu') {`;
const menuLogicEnd = `return [{json:{...e, intent:'SHOW_MENU', response:{replyText:msg, buttons:[{id:'MODE_SUR_PLACE',title:'🍽️ Sur place'},{id:'MODE_A_EMPORTER',title:'🛍️ À emporter'},{id:'MODE_LIVRAISON',title:'🛵 Livraison'}]}, debug:{riskFlags}}}];`;

const menuLogicNewReturn = `
  // P1-UX: Attach Menu Image
  const menuImg = ($env.MENU_IMAGE_URL || '').toString().trim();
  const attachments = [];
  if (menuImg) {
    attachments.push({ type: 'image', url: menuImg, mime: 'image/jpeg' });
  }
  return [{json:{...e, intent:'SHOW_MENU', response:{replyText:msg, attachments, buttons:[{id:'MODE_SUR_PLACE',title:'🍽️ Sur place'},{id:'MODE_A_EMPORTER',title:'🛍️ À emporter'},{id:'MODE_LIVRAISON',title:'🛵 Livraison'}]}, debug:{riskFlags}}}];`;

if (code.includes(menuLogicSig) && !code.includes('const menuImg =')) {
    // Replace the return statement in the Menu block
    // We need to match the specific return line we see in the file
    // Warning: explicit string match relies on exact whitespace. 
    // Let's use a robust replace
    code = code.replace(
        `return [{json:{...e, intent:'SHOW_MENU', response:{replyText:msg, buttons:[{id:'MODE_SUR_PLACE',title:'🍽️ Sur place'},{id:'MODE_A_EMPORTER',title:'🛍️ À emporter'},{id:'MODE_LIVRAISON',title:'🛵 Livraison'}]}, debug:{riskFlags}}}];`,
        menuLogicNewReturn.trim()
    );
    console.log('Patched Menu Image logic');
} else {
    console.log('Menu Image logic already present or signature not found');
}

// Patcher 2: Confirmation Prompt (Strict)
// Ensure "Confirmer la commande ?" is explicit
const confirmSig = `recap += \`\\nTotal : \${(total/100).toFixed(2)}€\\nConfirmer ?\`;`;
const confirmNew = `recap += \`\\nTotal : \${(total/100).toFixed(2)}€\\n\`;
  recap += (responseLocale === 'ar') ? 'هل تؤكد الطلب؟' : 'Confirmer la commande ?';`;

if (code.includes(confirmSig)) {
    code = code.replace(confirmSig, confirmNew.trim());
    console.log('Patched Confirmation Prompt');
} else {
    console.log('Confirmation prompt already patched or signature not found');
}

node.parameters.jsCode = code;

fs.writeFileSync(filePath, JSON.stringify(workflow, null, 2));
console.log('W4_CORE.json updated');
