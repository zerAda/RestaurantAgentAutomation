// =============================================================================
// Phase 19 — node --test for the PURE audit-hook.ts helper (AUD-01 + AUD-02).
//
// Drives the Strapi-free helper against an ephemeral Postgres + ephemeral Redis (no
// Strapi boot): SETs the canonical key, runs invalidateCache() and proves a GET returns
// nil (no stale grant — AUD-02), and asserts a row is written per op (AUD-01) incl. the
// product-module global path (tenant_id = NULL).
//
// Run via: bash scripts/test-phase19.sh   (boots PG + redis, exports the env vars below)
//   node --test --experimental-strip-types .../audit-hook.test.mjs
//
// FRAGILITY GUARD: audit-hook.ts is authored by Plan 19-02 (Wave 2). This file is committed
// in Wave 1 BEFORE the helper exists. The helper import is a DYNAMIC import() inside before()
// — NOT a static top-level import — so node --test can load this file without hard-crashing,
// and the helper/IO cases test.skip gracefully when the module or a service env var is absent.
// =============================================================================

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';

const TENANT = '00000000-0000-0000-0000-000000000001';
const MODULE = 'channel_whatsapp';
const KEY = `ralphe:entitlement:${TENANT}:${MODULE}`; // EXACT canonical key (ROADMAP:147 / ADR 0003)
// Byte-for-byte canonical key the Phase-20 GRD-01 GET must match — assert the constructed
// key equals this literal so a drift in TENANT/MODULE can never silently diverge from it.
const CANONICAL_KEY_LITERAL = 'ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp';

let helper = null;        // the dynamically-imported audit-hook module (null if not yet present)
let helperError = null;   // why the import failed (for the skip message)
let redis = null;
let knex = null;

const HAVE_REDIS = !!process.env.REDIS_PORT || !!process.env.REDIS_HOST || !!process.env.REDIS_URL;
const HAVE_PG = !!process.env.PGPORT || !!process.env.PGHOST;

before(async () => {
  // Dynamic import — committable before 19-02 lands audit-hook.ts.
  try {
    helper = await import('../audit-hook.ts');
  } catch (err) {
    helperError = err;
    helper = null;
  }

  if (helper && HAVE_REDIS) {
    const { default: Redis } = await import('ioredis');
    redis = process.env.REDIS_URL
      ? new Redis(process.env.REDIS_URL)
      : new Redis(parseInt(process.env.REDIS_PORT || '6379', 10), process.env.REDIS_HOST || '127.0.0.1');
  }

  if (helper && HAVE_PG) {
    const { default: Knex } = await import('knex');
    knex = Knex({
      client: 'pg',
      connection: {
        host: process.env.PGHOST || '127.0.0.1',
        port: parseInt(process.env.PGPORT || '5432', 10),
        user: process.env.PGUSER || 'postgres',
        password: process.env.PGPASSWORD || undefined,
        database: process.env.PGDATABASE || 'postgres',
      },
    });
  }
});

after(async () => {
  if (redis) { try { await redis.quit(); } catch { /* ignore */ } }
  if (knex) { try { await knex.destroy(); } catch { /* ignore */ } }
});

// ---- Cache-key contract (no IO, no helper required) ----

test('canonical cache key is byte-for-byte ralphe:entitlement:{tenant_id}:{module_key}', () => {
  assert.equal(KEY, CANONICAL_KEY_LITERAL, 'constructed key must match the Phase-20 GRD-01 GET literal');
});

// ---- Pure unit cases (no IO) ----

test('deriveAction: null->non-null is created; non-null->null is deleted', { skip: !helper && (helperError ? 'audit-hook.ts not present yet' : true) }, () => {
  assert.equal(helper.deriveAction(null, { enabled: true }), 'created');
  assert.equal(helper.deriveAction({ enabled: true }, null), 'deleted');
});

test('deriveAction: enabled toggles map to enabled/disabled; benign change is config_changed', { skip: !helper && 'audit-hook.ts not present yet' }, () => {
  assert.equal(helper.deriveAction({ enabled: true }, { enabled: false }), 'disabled');
  assert.equal(helper.deriveAction({ enabled: false }, { enabled: true }), 'enabled');
  assert.equal(helper.deriveAction({ enabled: true, notes: 'a' }, { enabled: true, notes: 'b' }), 'config_changed');
});

test('validateTenantId: canonical UUID returns it; "default" and "" throw; NULL is allowed (global)', { skip: !helper && 'audit-hook.ts not present yet' }, () => {
  assert.equal(helper.validateTenantId(TENANT), TENANT);
  assert.throws(() => helper.validateTenantId('default'));
  assert.throws(() => helper.validateTenantId(''));
  // CORRECTION (Blocker B): a null tenant_id is the legitimate platform/global value — must NOT throw.
  assert.equal(helper.validateTenantId(null), null);
  assert.equal(helper.validateTenantId(undefined), null);
});

// ---- IO cases (ephemeral redis / pg) ----

test('invalidateCache: SET canonical key -> invalidateCache -> GET nil (AUD-02, no stale grant)', { skip: (!helper && 'audit-hook.ts not present yet') || (!redis && 'no ephemeral redis') }, async () => {
  await redis.set(KEY, '1');
  assert.equal(await redis.get(KEY), '1', 'precondition: key is set');
  await helper.invalidateCache(redis, TENANT, MODULE);
  const after = await redis.get(KEY);
  assert.equal(after, null, 'stale grant survived invalidateCache — AUD-02 regression');
});

test('writeAuditRow: writes one created row (old null, new set) for the canonical tenant (AUD-01)', { skip: (!helper && 'audit-hook.ts not present yet') || (!knex && 'no ephemeral pg') }, async () => {
  const before = Number((await knex('entitlement_audit_log')
    .where({ tenant_id: TENANT, module_key: MODULE }).count('* as c'))[0].c);
  await helper.writeAuditRow(knex, {
    tenant_id: TENANT, module_key: MODULE, action: 'created',
    changed_by: 'system', old_value: null, new_value: { enabled: true },
  });
  const rows = await knex('entitlement_audit_log')
    .where({ tenant_id: TENANT, module_key: MODULE, action: 'created' })
    .orderBy('id', 'desc').limit(1);
  const after = Number((await knex('entitlement_audit_log')
    .where({ tenant_id: TENANT, module_key: MODULE }).count('* as c'))[0].c);
  assert.equal(after, before + 1, 'exactly one audit row added');
  assert.equal(rows[0].old_value, null, 'created row has null old_value');
  assert.notEqual(rows[0].new_value, null, 'created row has new_value');
});

test('writeAuditRow: product-module global row writes tenant_id IS NULL (Blocker B; nullable FK accepts)', { skip: (!helper && 'audit-hook.ts not present yet') || (!knex && 'no ephemeral pg') }, async () => {
  await helper.writeAuditRow(knex, {
    tenant_id: null, module_key: MODULE, action: 'config_changed',
    changed_by: 'system', old_value: { enabled_globally: true }, new_value: { enabled_globally: false },
  });
  const nullRows = Number((await knex('entitlement_audit_log').whereNull('tenant_id').count('* as c'))[0].c);
  assert.ok(nullRows >= 1, 'global product-module row written with tenant_id IS NULL');
  const sentinel = Number((await knex('entitlement_audit_log')
    .where({ tenant_id: '00000000-0000-0000-0000-000000000000' }).count('* as c'))[0].c);
  assert.equal(sentinel, 0, 'all-zero sentinel must NOT be used for globals');
});

test('writeAuditRow: a non-canonical tenant_id throws BEFORE insert (fail-loud, no row)', { skip: (!helper && 'audit-hook.ts not present yet') || (!knex && 'no ephemeral pg') }, async () => {
  const before = Number((await knex('entitlement_audit_log').count('* as c'))[0].c);
  await assert.rejects(
    () => helper.writeAuditRow(knex, { tenant_id: 'default', module_key: MODULE, action: 'created' }),
    'a non-canonical tenant_id must throw pre-insert',
  );
  const after = Number((await knex('entitlement_audit_log').count('* as c'))[0].c);
  assert.equal(after, before, 'no row written for a bad tenant_id (validate-throw-pre-write)');
});

test('fail-loud: writeAuditRow surfaces a rejecting knex (no silent swallow)', { skip: !helper && 'audit-hook.ts not present yet' }, async () => {
  // Inject a knex stub whose insert rejects — the helper must propagate, not swallow.
  const rejectingKnex = () => ({ insert: () => Promise.reject(new Error('db down')) });
  await assert.rejects(
    () => helper.writeAuditRow(rejectingKnex, {
      tenant_id: TENANT, module_key: MODULE, action: 'created', new_value: { enabled: true },
    }),
    /db down/,
    'writeAuditRow must surface the underlying error, not swallow it',
  );
});

test('fail-loud: invalidateCache surfaces a rejecting redis (no silent swallow)', { skip: !helper && 'audit-hook.ts not present yet' }, async () => {
  const rejectingRedis = { del: () => Promise.reject(new Error('redis down')) };
  await assert.rejects(
    () => helper.invalidateCache(rejectingRedis, TENANT, MODULE),
    /redis down/,
    'invalidateCache must surface the underlying error, not swallow it',
  );
});
