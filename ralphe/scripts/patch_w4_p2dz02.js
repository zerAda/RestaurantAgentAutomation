#!/usr/bin/env node
/**
 * P2-DZ-02: Patch W4_CORE.json to add WhatsApp location pin support
 *
 * This patch:
 * 1. Adds location extraction from message attachments
 * 2. Updates delivery_quote call to use delivery_quote_v2 with coordinates
 * 3. Adds location-based zone matching logic
 *
 * Usage: node scripts/patch_w4_p2dz02.js
 */

const fs = require('fs');
const path = require('path');

const WORKFLOW_PATH = path.join(__dirname, '..', 'workflows', 'W4_CORE.json');
const BACKUP_PATH = WORKFLOW_PATH + '.bak.p2dz02';

function main() {
  console.log('[P2-DZ-02] Patching W4_CORE.json for WhatsApp location support...\n');

  if (!fs.existsSync(WORKFLOW_PATH)) {
    console.error(`ERROR: ${WORKFLOW_PATH} not found`);
    process.exit(1);
  }

  // Create backup
  const original = fs.readFileSync(WORKFLOW_PATH, 'utf8');
  fs.writeFileSync(BACKUP_PATH, original);
  console.log(`[OK] Backup created: ${BACKUP_PATH}`);

  let workflow;
  try {
    workflow = JSON.parse(original);
  } catch (e) {
    console.error('ERROR: Failed to parse workflow JSON:', e.message);
    process.exit(1);
  }

  let modified = false;

  // Find and update the Parse Message node to extract location
  const parseNode = workflow.nodes.find(n =>
    n.name && n.name.includes('Parse') && n.type === 'n8n-nodes-base.code'
  );

  if (parseNode && parseNode.parameters && parseNode.parameters.jsCode) {
    const code = parseNode.parameters.jsCode;

    // Check if location extraction is already present
    if (!code.includes('extractLocationFromAttachments')) {
      console.log('[INFO] Adding location extraction helper to Parse node...');

      // Add location extraction function at the beginning
      const locationHelper = `
// P2-DZ-02: Extract location from message attachments
function extractLocationFromAttachments(attachments) {
  if (!Array.isArray(attachments)) return null;
  const loc = attachments.find(a => a && a.type === 'location');
  if (!loc) return null;
  return {
    latitude: loc.latitude || null,
    longitude: loc.longitude || null,
    name: loc.name || '',
    address: loc.address || ''
  };
}
`;
      parseNode.parameters.jsCode = locationHelper + '\n' + code;
      modified = true;
      console.log('[OK] Location extraction helper added');
    }
  }

  // Find the delivery quote node and update to use v2 function
  const deliveryQuoteNode = workflow.nodes.find(n =>
    n.parameters && n.parameters.query && n.parameters.query.includes('delivery_quote')
  );

  if (deliveryQuoteNode) {
    const oldQuery = deliveryQuoteNode.parameters.query;

    // Check if already using v2
    if (!oldQuery.includes('delivery_quote_v2')) {
      console.log('[INFO] Updating delivery_quote to delivery_quote_v2...');

      // Update to v2 with location support
      deliveryQuoteNode.parameters.query =
        "SELECT * FROM public.delivery_quote_v2($1::uuid,$2::text,$3::text,$4::numeric,$5::numeric,$6::int);";

      // Update query params to include location
      deliveryQuoteNode.parameters.additionalFields = {
        queryParams: "={{[$json.restaurantId, $json.state.delivery?.wilaya || null, $json.state.delivery?.commune || null, $json.state.delivery?.location?.latitude || null, $json.state.delivery?.location?.longitude || null, ($json.state.lastTotalCents || 0)]}}"
      };

      modified = true;
      console.log('[OK] delivery_quote updated to v2 with location support');
    } else {
      console.log('[SKIP] delivery_quote_v2 already in use');
    }
  }

  // Find the state builder node and add location handling
  const stateNodes = workflow.nodes.filter(n =>
    n.type === 'n8n-nodes-base.code' &&
    n.parameters?.jsCode?.includes('state') &&
    n.parameters?.jsCode?.includes('delivery')
  );

  for (const node of stateNodes) {
    if (node.parameters?.jsCode && !node.parameters.jsCode.includes('location.latitude')) {
      console.log(`[INFO] Checking node "${node.name}" for location state handling...`);

      // Check if this node handles delivery state
      if (node.parameters.jsCode.includes("delivery") &&
          node.parameters.jsCode.includes("state") &&
          !node.parameters.jsCode.includes("extractLocationFromAttachments")) {

        // Add location extraction to state handling
        const locationStateCode = `
// P2-DZ-02: Extract and store location from attachments
const msgLocation = typeof extractLocationFromAttachments === 'function'
  ? extractLocationFromAttachments($json.message?.attachments || $json.attachments || [])
  : null;

if (msgLocation && msgLocation.latitude && msgLocation.longitude) {
  state.delivery = state.delivery || {};
  state.delivery.location = msgLocation;
  // Try to parse address for wilaya/commune hints
  if (msgLocation.address) {
    const addrParts = msgLocation.address.split(',').map(s => s.trim());
    if (addrParts.length >= 2) {
      state.delivery.addressHint = msgLocation.address;
    }
  }
}
`;
        // Find a good insertion point
        const deliveryIdx = node.parameters.jsCode.indexOf('delivery');
        if (deliveryIdx > -1) {
          // Insert before first delivery reference
          const insertPoint = node.parameters.jsCode.lastIndexOf('\n', deliveryIdx);
          if (insertPoint > -1) {
            node.parameters.jsCode =
              node.parameters.jsCode.slice(0, insertPoint) +
              locationStateCode +
              node.parameters.jsCode.slice(insertPoint);
            modified = true;
            console.log(`[OK] Location state handling added to "${node.name}"`);
          }
        }
      }
    }
  }

  // Add a new node for location zone lookup if not exists
  const locationLookupNode = workflow.nodes.find(n =>
    n.name && n.name.includes('Location Zone Lookup')
  );

  if (!locationLookupNode) {
    console.log('[INFO] Adding Location Zone Lookup node...');

    // Find the delivery quote node position to place nearby
    const quoteNode = workflow.nodes.find(n =>
      n.parameters?.query?.includes('delivery_quote')
    );

    const basePos = quoteNode?.position || [800, 400];

    const newNode = {
      parameters: {
        operation: "executeQuery",
        query: `SELECT * FROM public.location_to_zone($1::uuid, $2::numeric, $3::numeric);`,
        additionalFields: {
          queryParams: "={{[$json.restaurantId, $json.state?.delivery?.location?.latitude, $json.state?.delivery?.location?.longitude]}}"
        }
      },
      id: "p2dz02-location-zone-lookup",
      name: "DQ - Location Zone Lookup",
      type: "n8n-nodes-base.postgres",
      typeVersion: 2,
      position: [basePos[0] + 200, basePos[1] - 100],
      credentials: {
        postgres: {
          id: "1",
          name: "Postgres"
        }
      }
    };

    workflow.nodes.push(newNode);
    modified = true;
    console.log('[OK] Location Zone Lookup node added');
  }

  // Save if modified
  if (modified) {
    fs.writeFileSync(WORKFLOW_PATH, JSON.stringify(workflow, null, 2));
    console.log(`\n[SUCCESS] W4_CORE.json patched for P2-DZ-02`);
    console.log('Changes:');
    console.log('  - Location extraction from WhatsApp attachments');
    console.log('  - delivery_quote upgraded to v2 with coordinate support');
    console.log('  - Location zone lookup node added');
  } else {
    console.log('\n[INFO] No changes needed - W4_CORE.json already up to date');
  }
}

main();
