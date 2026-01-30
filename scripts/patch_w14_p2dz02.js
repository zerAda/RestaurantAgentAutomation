#!/usr/bin/env node
/**
 * P2-DZ-02: Patch W14_ADMIN_WA_SUPPORT_CONSOLE.json for enhanced zone commands
 *
 * This patch adds:
 * - !zone coords <wilaya> <commune> <lat> <lng> - Set zone coordinates
 * - !zone radius <wilaya> <commune> <km> - Set zone radius
 * - !zone lookup <lat> <lng> - Test location to zone matching
 * - !address normalize <text> - Test address normalization
 *
 * Usage: node scripts/patch_w14_p2dz02.js
 */

const fs = require('fs');
const path = require('path');

const WORKFLOW_PATH = path.join(__dirname, '..', 'workflows', 'W14_ADMIN_WA_SUPPORT_CONSOLE.json');
const BACKUP_PATH = WORKFLOW_PATH + '.bak.p2dz02';

function main() {
  console.log('[P2-DZ-02] Patching W14 for enhanced zone commands...\n');

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

  // Find the command parser node
  const parserNode = workflow.nodes.find(n =>
    n.type === 'n8n-nodes-base.code' &&
    n.parameters?.jsCode?.includes('!zone') &&
    n.parameters?.jsCode?.includes('cmd')
  );

  if (parserNode && parserNode.parameters?.jsCode) {
    const code = parserNode.parameters.jsCode;

    // Check if new commands already exist
    if (!code.includes('zone_coords') && !code.includes('zone_lookup')) {
      console.log('[INFO] Adding new zone commands to parser...');

      // Find the command parsing section and add new commands
      const newCommands = `
  // P2-DZ-02: Enhanced zone commands
  } else if (cmd === '!zone' && args[0] === 'coords' && args.length >= 5) {
    // !zone coords <wilaya> <commune> <lat> <lng>
    return [{json:{...e, adminAction: 'zone_coords', zoneWilaya: args[1], zoneCommune: args[2], zoneLat: parseFloat(args[3]), zoneLng: parseFloat(args[4])}}];
  } else if (cmd === '!zone' && args[0] === 'radius' && args.length >= 4) {
    // !zone radius <wilaya> <commune> <km>
    return [{json:{...e, adminAction: 'zone_radius', zoneWilaya: args[1], zoneCommune: args[2], zoneRadius: parseFloat(args[3])}}];
  } else if (cmd === '!zone' && args[0] === 'lookup' && args.length >= 3) {
    // !zone lookup <lat> <lng>
    return [{json:{...e, adminAction: 'zone_lookup', lookupLat: parseFloat(args[1]), lookupLng: parseFloat(args[2])}}];
  } else if (cmd === '!address' && args[0] === 'normalize') {
    // !address normalize <text...>
    return [{json:{...e, adminAction: 'address_normalize', addressText: args.slice(1).join(' ')}}];
`;

      // Find good insertion point (before the final else)
      const elseIdx = code.lastIndexOf('} else {');
      if (elseIdx > -1) {
        parserNode.parameters.jsCode =
          code.slice(0, elseIdx) +
          newCommands +
          code.slice(elseIdx);
        modified = true;
        console.log('[OK] New zone commands added to parser');
      }
    } else {
      console.log('[SKIP] Zone commands already present in parser');
    }
  }

  // Add new database nodes for the commands
  const existingNodes = workflow.nodes.map(n => n.id);

  // Zone coords update node
  if (!existingNodes.includes('p2dz02-zone-coords')) {
    console.log('[INFO] Adding zone coords update node...');

    workflow.nodes.push({
      parameters: {
        operation: "executeQuery",
        query: `UPDATE public.delivery_zones
SET center_lat = $3::numeric, center_lng = $4::numeric, updated_at = now()
WHERE restaurant_id = $1::uuid
  AND lower(wilaya) = lower($2::text)
  AND lower(commune) = lower($5::text)
RETURNING zone_id, wilaya, commune, center_lat, center_lng;`,
        additionalFields: {
          queryParams: "={{[$json.restaurantId, $json.zoneWilaya, $json.zoneLat, $json.zoneLng, $json.zoneCommune]}}"
        }
      },
      id: "p2dz02-zone-coords",
      name: "DB - Zone Set Coords",
      type: "n8n-nodes-base.postgres",
      typeVersion: 2,
      position: [1200, 600],
      credentials: { postgres: { id: "1", name: "Postgres" } }
    });
    modified = true;
  }

  // Zone radius update node
  if (!existingNodes.includes('p2dz02-zone-radius')) {
    console.log('[INFO] Adding zone radius update node...');

    workflow.nodes.push({
      parameters: {
        operation: "executeQuery",
        query: `UPDATE public.delivery_zones
SET radius_km = $3::numeric, updated_at = now()
WHERE restaurant_id = $1::uuid
  AND lower(wilaya) = lower($2::text)
  AND lower(commune) = lower($4::text)
RETURNING zone_id, wilaya, commune, radius_km;`,
        additionalFields: {
          queryParams: "={{[$json.restaurantId, $json.zoneWilaya, $json.zoneRadius, $json.zoneCommune]}}"
        }
      },
      id: "p2dz02-zone-radius",
      name: "DB - Zone Set Radius",
      type: "n8n-nodes-base.postgres",
      typeVersion: 2,
      position: [1200, 700],
      credentials: { postgres: { id: "1", name: "Postgres" } }
    });
    modified = true;
  }

  // Zone lookup node
  if (!existingNodes.includes('p2dz02-zone-lookup')) {
    console.log('[INFO] Adding zone lookup node...');

    workflow.nodes.push({
      parameters: {
        operation: "executeQuery",
        query: `SELECT * FROM public.location_to_zone($1::uuid, $2::numeric, $3::numeric);`,
        additionalFields: {
          queryParams: "={{[$json.restaurantId, $json.lookupLat, $json.lookupLng]}}"
        }
      },
      id: "p2dz02-zone-lookup",
      name: "DB - Zone Lookup",
      type: "n8n-nodes-base.postgres",
      typeVersion: 2,
      position: [1200, 800],
      credentials: { postgres: { id: "1", name: "Postgres" } }
    });
    modified = true;
  }

  // Address normalize node
  if (!existingNodes.includes('p2dz02-address-normalize')) {
    console.log('[INFO] Adding address normalize node...');

    workflow.nodes.push({
      parameters: {
        operation: "executeQuery",
        query: `SELECT * FROM public.normalize_address($1::text, NULL, NULL);`,
        additionalFields: {
          queryParams: "={{[$json.addressText]}}"
        }
      },
      id: "p2dz02-address-normalize",
      name: "DB - Address Normalize",
      type: "n8n-nodes-base.postgres",
      typeVersion: 2,
      position: [1200, 900],
      credentials: { postgres: { id: "1", name: "Postgres" } }
    });
    modified = true;
  }

  // Update help text if present
  const helpNode = workflow.nodes.find(n =>
    n.parameters?.jsCode?.includes('!help') ||
    n.parameters?.responseBody?.includes('!help')
  );

  if (helpNode && helpNode.parameters?.jsCode) {
    if (!helpNode.parameters.jsCode.includes('!zone coords')) {
      console.log('[INFO] Updating help text with new commands...');

      const newHelp = `
!zone coords <wilaya> <commune> <lat> <lng> - Set zone center coordinates
!zone radius <wilaya> <commune> <km> - Set zone matching radius
!zone lookup <lat> <lng> - Test location to zone matching
!address normalize <text> - Test address normalization
`;
      // Find help text and append
      if (helpNode.parameters.jsCode.includes('ZONE')) {
        helpNode.parameters.jsCode = helpNode.parameters.jsCode.replace(
          /(ZONE[^`]*)(```|'|")/,
          `$1\n${newHelp}$2`
        );
        modified = true;
        console.log('[OK] Help text updated');
      }
    }
  }

  // Save if modified
  if (modified) {
    fs.writeFileSync(WORKFLOW_PATH, JSON.stringify(workflow, null, 2));
    console.log(`\n[SUCCESS] W14 patched for P2-DZ-02`);
    console.log('New commands:');
    console.log('  - !zone coords <wilaya> <commune> <lat> <lng>');
    console.log('  - !zone radius <wilaya> <commune> <km>');
    console.log('  - !zone lookup <lat> <lng>');
    console.log('  - !address normalize <text>');
  } else {
    console.log('\n[INFO] No changes needed - W14 already up to date');
  }
}

main();
