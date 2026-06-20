/**
 * node --test for scripts/check-module-keys.mjs — exercises the pure helpers on
 * fixture strings (no shelling out to the CLI) plus one live-invariant test that
 * reads the REAL manifest + seeder and asserts they are identical.
 *
 * Run via: /opt/node22/bin/node --test scripts/__tests__/check-module-keys.test.mjs
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

import {
  loadCanonicalKeys,
  extractSeederKeys,
  extractAppTsxKeys,
  extractWorkflowKeys,
  findGhosts,
  setsEqual,
} from '../check-module-keys.mjs';

const here = dirname(fileURLToPath(import.meta.url)); // .../scripts/__tests__
const repoRoot = resolve(here, '..', '..');

const CANONICAL_FIXTURE = JSON.stringify({
  modules: [
    { key: 'platform_runtime' },
    { key: 'order_bot_core' },
    { key: 'kiosk_instore' },
    { key: 'voice' },
    { key: 'admin_ai_intelligence' },
    { key: 'growth_marketing' },
    { key: 'payment' },
  ],
});

test('loadCanonicalKeys parses modules[].key into a Set', () => {
  const set = loadCanonicalKeys(CANONICAL_FIXTURE);
  assert.ok(set instanceof Set);
  assert.equal(set.size, 7);
  assert.ok(set.has('kiosk_instore'));
  assert.ok(set.has('order_bot_core'));
  assert.ok(!set.has('feature_kiosk'));
});

test('extractSeederKeys pulls key: \'...\' from SAAS_MODULES text', () => {
  const seederText = `
    export const SAAS_MODULES = [
      { key: 'platform_runtime', tier: 'shared_core' },
      { key: 'order_bot_core', tier: 'product_core' },
      { key: 'kiosk_instore', tier: 'addon' },
    ];
  `;
  const set = extractSeederKeys(seederText);
  assert.deepEqual([...set].sort(), ['kiosk_instore', 'order_bot_core', 'platform_runtime']);
});

test('extractAppTsxKeys returns every hasModule(...) key', () => {
  const appText = `
    {hasModule('kiosk_instore') && <Nav/>}
    {hasModule('admin_ai_intelligence') && <Nav/>}
    {hasModule("growth_marketing") && <Nav/>}
  `;
  assert.deepEqual(extractAppTsxKeys(appText), [
    'kiosk_instore',
    'admin_ai_intelligence',
    'growth_marketing',
  ]);
});

test('extractWorkflowKeys matches BOTH the n8n expression form and the JSON form', () => {
  const exprText = `"json": "={{ { module_key: 'voice', tenant_id: x } }}"`;
  assert.deepEqual(extractWorkflowKeys(exprText), ['voice']);

  const jsonText = `{ "module_key": "kiosk_instore" }`;
  assert.deepEqual(extractWorkflowKeys(jsonText), ['kiosk_instore']);

  // De-duplicates across both forms.
  const both = `module_key: 'voice' ... "module_key": "voice"`;
  assert.deepEqual(extractWorkflowKeys(both), ['voice']);
});

test('findGhosts flags the ghost and NOT the real key', () => {
  const canonical = loadCanonicalKeys(CANONICAL_FIXTURE);
  assert.deepEqual(findGhosts(['kiosk_instore', 'feature_kiosk'], canonical), ['feature_kiosk']);
});

test('findGhosts allows orphan/ungated canonical keys (one-directional)', () => {
  const canonical = loadCanonicalKeys(CANONICAL_FIXTURE);
  // payment is canonical but never referenced — that is FINE (not a ghost).
  assert.deepEqual(findGhosts(['payment'], canonical), []);
});

test('setsEqual reports onlyA/onlyB when the two source-of-truth sets diverge', () => {
  const a = new Set(['platform_runtime', 'order_bot_core', 'voice']);
  const b = new Set(['platform_runtime', 'order_bot_core', 'kiosk_instore']);
  const res = setsEqual(a, b);
  assert.equal(res.equal, false);
  assert.deepEqual(res.onlyA, ['voice']);
  assert.deepEqual(res.onlyB, ['kiosk_instore']);
});

test('setsEqual.equal is true for identical sets', () => {
  const a = new Set(['platform_runtime', 'voice']);
  const b = new Set(['voice', 'platform_runtime']);
  assert.equal(setsEqual(a, b).equal, true);
});

test('a synthetic ghost fixture produces a violation (the checker logic flags it)', () => {
  const canonical = loadCanonicalKeys(CANONICAL_FIXTURE);
  const appKeys = extractAppTsxKeys(`{hasModule('addon_kitchen_display') && <Nav/>}`);
  const wfKeys = extractWorkflowKeys(`module_key: 'channel_voice'`);
  const ghosts = findGhosts([...appKeys, ...wfKeys], canonical);
  assert.deepEqual(ghosts.sort(), ['addon_kitchen_display', 'channel_voice']);
});

test('LIVE invariant: the real manifest key set == the real seeder key set', () => {
  const manifestPath = join(repoRoot, 'config', 'product_modules.json');
  const seederPath = join(
    repoRoot,
    'inventory-cms',
    'src',
    'bootstrap-seeds',
    'saas-entitlements.ts'
  );
  const canonical = loadCanonicalKeys(readFileSync(manifestPath, 'utf8'));
  const seeder = extractSeederKeys(readFileSync(seederPath, 'utf8'));
  const res = setsEqual(canonical, seeder);
  assert.equal(
    res.equal,
    true,
    `manifest != seeder; onlyManifest=[${res.onlyA}] onlySeeder=[${res.onlyB}]`
  );
  assert.equal(canonical.size, 15);
});

test('LIVE post-fix tree: every referenced key in App.tsx + workflows is canonical', () => {
  const manifestPath = join(repoRoot, 'config', 'product_modules.json');
  const canonical = loadCanonicalKeys(readFileSync(manifestPath, 'utf8'));

  const appText = readFileSync(join(repoRoot, 'admin-dashboard', 'src', 'App.tsx'), 'utf8');
  const referenced = [...extractAppTsxKeys(appText)];

  const wfFor = (name) =>
    extractWorkflowKeys(readFileSync(join(repoRoot, 'workflows', name), 'utf8'));
  for (const wf of ['W_KIOSK_ORDER.json', 'W_ORDER_FINALIZER.json', 'W30_VOICE_CALL_INIT.json']) {
    referenced.push(...wfFor(wf));
  }

  assert.deepEqual(findGhosts(referenced, canonical), []);
});
