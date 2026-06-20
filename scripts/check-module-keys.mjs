#!/usr/bin/env node
/**
 * check-module-keys.mjs — ENT-02 module-key consistency check (dependency-free ESM).
 *
 * Asserts that EVERY module_key referenced in admin-dashboard/src/App.tsx AND in
 * workflows/*.json exists in the canonical source-of-truth set
 * (config/product_modules.json modules[].key), AND that the manifest key set is
 * IDENTICAL to the seeder set (inventory-cms/src/bootstrap-seeds/saas-entitlements.ts
 * SAAS_MODULES[].key) — the invariant the seeder's own comment (L13-16) declares.
 *
 * The check is ONE-DIRECTIONAL: every *referenced* key must EXIST in the canonical
 * set (orphan/ungated manifest keys are allowed). A referenced key that is NOT in
 * the canonical set is a "ghost" — a fail-closed silent deny under W0_MODULE_GUARD.
 *
 * Pure helpers are exported for unit testing on fixture strings (node --test);
 * the CLI body (read repo files + process.exit) runs ONLY when invoked directly.
 */

import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

// ─────────────────────────── Pure helpers (unit-testable) ───────────────────────────

/**
 * Parse config/product_modules.json text → Set of modules[].key.
 * @param {string} manifestText
 * @returns {Set<string>}
 */
export function loadCanonicalKeys(manifestText) {
  const parsed = JSON.parse(manifestText);
  const mods = Array.isArray(parsed.modules) ? parsed.modules : [];
  return new Set(mods.map((m) => m.key).filter((k) => typeof k === 'string'));
}

/**
 * Regex-extract the SAAS_MODULES[].key values from saas-entitlements.ts text.
 * Matches `key: '...'` (the seeder's object-literal form).
 * @param {string} seederText
 * @returns {Set<string>}
 */
export function extractSeederKeys(seederText) {
  const out = new Set();
  const re = /key:\s*'([^']+)'/g;
  let m;
  while ((m = re.exec(seederText)) !== null) {
    out.add(m[1]);
  }
  return out;
}

/**
 * Regex-extract every hasModule('<key>') reference from App.tsx text.
 * @param {string} appText
 * @returns {string[]}
 */
export function extractAppTsxKeys(appText) {
  const out = [];
  const re = /hasModule\(['"]([^'"]+)['"]\)/g;
  let m;
  while ((m = re.exec(appText)) !== null) {
    out.push(m[1]);
  }
  return out;
}

/**
 * Regex-extract every module_key reference from a workflow JSON text.
 * Matches BOTH the n8n expression form `module_key: '<key>'` AND the
 * raw JSON form `"module_key": "<key>"`. De-duplicated.
 * @param {string} jsonText
 * @returns {string[]}
 */
export function extractWorkflowKeys(jsonText) {
  const out = new Set();
  const exprRe = /module_key:\s*'([^']+)'/g;
  const jsonRe = /"module_key"\s*:\s*"([^"]+)"/g;
  let m;
  while ((m = exprRe.exec(jsonText)) !== null) out.add(m[1]);
  while ((m = jsonRe.exec(jsonText)) !== null) out.add(m[1]);
  return Array.from(out);
}

/**
 * Return the referenced keys that are NOT members of the canonical set (ghosts).
 * @param {string[]} referenced
 * @param {Set<string>} canonical
 * @returns {string[]}
 */
export function findGhosts(referenced, canonical) {
  return referenced.filter((k) => !canonical.has(k));
}

/**
 * Symmetric-difference comparison of two Sets.
 * @param {Set<string>} a
 * @param {Set<string>} b
 * @returns {{equal: boolean, onlyA: string[], onlyB: string[]}}
 */
export function setsEqual(a, b) {
  const onlyA = [...a].filter((k) => !b.has(k));
  const onlyB = [...b].filter((k) => !a.has(k));
  return { equal: onlyA.length === 0 && onlyB.length === 0, onlyA, onlyB };
}

// ─────────────────────────── CLI body (direct-run only) ───────────────────────────

function runCli() {
  const here = dirname(fileURLToPath(import.meta.url)); // .../scripts
  const repoRoot = resolve(here, '..');

  const manifestPath = join(repoRoot, 'config', 'product_modules.json');
  const seederPath = join(
    repoRoot,
    'inventory-cms',
    'src',
    'bootstrap-seeds',
    'saas-entitlements.ts'
  );
  const appTsxPath = join(repoRoot, 'admin-dashboard', 'src', 'App.tsx');
  const workflowsDir = join(repoRoot, 'workflows');

  const canonical = loadCanonicalKeys(readFileSync(manifestPath, 'utf8'));
  const seeder = extractSeederKeys(readFileSync(seederPath, 'utf8'));

  // 1. Manifest == seeder invariant.
  const eq = setsEqual(canonical, seeder);
  if (!eq.equal) {
    console.error('FAIL: manifest key set != seeder key set');
    if (eq.onlyA.length) console.error(`  only in manifest: ${eq.onlyA.join(', ')}`);
    if (eq.onlyB.length) console.error(`  only in seeder:   ${eq.onlyB.join(', ')}`);
    process.exit(1);
  }

  // 2. Collect every referenced key with its source file.
  /** @type {{file: string, key: string}[]} */
  const refs = [];
  const appKeys = extractAppTsxKeys(readFileSync(appTsxPath, 'utf8'));
  for (const key of appKeys) refs.push({ file: 'admin-dashboard/src/App.tsx', key });

  const workflowFiles = readdirSync(workflowsDir).filter((f) => f.endsWith('.json'));
  for (const f of workflowFiles) {
    const keys = extractWorkflowKeys(readFileSync(join(workflowsDir, f), 'utf8'));
    for (const key of keys) refs.push({ file: `workflows/${f}`, key });
  }

  // 3. Find ghosts (referenced but not canonical).
  const ghosts = refs.filter((r) => !canonical.has(r.key));
  if (ghosts.length) {
    console.error(`FAIL: ${ghosts.length} ghost module_key reference(s) not in the manifest/seeder:`);
    for (const g of ghosts) console.error(`  ${g.file}: '${g.key}'`);
    process.exit(1);
  }

  console.log(
    `PASS: ${refs.length} referenced module_key(s) across App.tsx + ${workflowFiles.length} workflows ` +
      `all exist in the ${canonical.size}-key manifest (== seeder set). No ghosts.`
  );
  process.exit(0);
}

// Run the CLI only when invoked directly (not when imported by the test).
const invokedDirectly =
  typeof process.argv[1] === 'string' &&
  import.meta.url === `file://${process.argv[1]}`;
if (invokedDirectly) {
  runCli();
}
