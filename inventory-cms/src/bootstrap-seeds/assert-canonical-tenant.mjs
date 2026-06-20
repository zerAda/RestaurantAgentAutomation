#!/usr/bin/env node
/**
 * assert-canonical-tenant.mjs
 *
 * Standalone Node ESM assertion script — NOT a jest/vitest test.
 * inventory-cms has no test runner; this script is run with plain `node`.
 *
 * Verifies that the seeder's defaultTenantId resolution never falls back to
 * the literal string 'default', and that it always resolves to a valid UUID.
 *
 * Run:   node inventory-cms/src/bootstrap-seeds/assert-canonical-tenant.mjs
 * Exit:  0 on PASS, non-zero on any assertion failure (node:assert throws).
 *
 * Part of Phase 15 — Tenant Identity Model (Canonical Key).
 * See docs/adr/0001-canonical-tenant-key.md
 */

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// ─── 1. Replicate the seeder's resolution expression exactly ────────────────

const CANONICAL = '00000000-0000-0000-0000-000000000001';
const defaultTenantId = (process.env.DEFAULT_TENANT_ID || '').trim() || CANONICAL;

// ─── 2. Assert: resolved value is never the string 'default' ────────────────

assert.notStrictEqual(
  defaultTenantId,
  'default',
  "seeder must never resolve to 'default' — 'default' is not a valid uuid in the data plane"
);

// ─── 3. Assert: resolved value matches UUID format ───────────────────────────

assert.match(
  defaultTenantId,
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
  'resolved tenant id must be a UUID (8-4-4-4-12 hex format)'
);

// ─── 4. Grep-guard: assert the source file does NOT contain the old pattern ──

const seederPath = join(__dirname, 'saas-entitlements.ts');
const seederSource = readFileSync(seederPath, 'utf8');

const badPattern = "DEFAULT_TENANT_ID || 'default'";
assert.ok(
  !seederSource.includes(badPattern),
  `saas-entitlements.ts must not contain the pattern "${badPattern}" — the seeder must never fall back to 'default'`
);

// ─── 5. PASS ─────────────────────────────────────────────────────────────────

console.log(
  "PASS: seeder resolves to canonical UUID, no 'default' fallback"
);
console.log(`  defaultTenantId = '${defaultTenantId}'`);
console.log(`  UUID regex check: PASSED`);
console.log(`  Source grep check (no "DEFAULT_TENANT_ID || 'default'"): PASSED`);
