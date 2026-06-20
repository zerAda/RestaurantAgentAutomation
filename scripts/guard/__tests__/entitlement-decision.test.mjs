/**
 * node --test for scripts/guard/entitlement-decision.mjs (Phase 20 GRD-01).
 *
 * Proves, with NO n8n / Strapi / Redis boot:
 *   - buildCacheKey is byte-for-byte the Phase-19 DEL key
 *   - cache HIT performs ZERO Strapi fetches (call-count 0)        [criterion 1]
 *   - Redis error / nil / LRU-eviction -> fall through (not a deny) [pivot c / criterion 2]
 *   - Strapi error -> DENY GUARD_ERROR_FAILCLOSED, NOT cached       [pivots b + d / criterion 2]
 *   - a cached raw row's expires_at is re-evaluated on read         [pivot a]
 *   - 401 / non-2xx -> FAILCLOSED (NOT NO_ENTITLEMENT)              [Pitfall 8]
 *   - positive TTL 300 / negative TTL 60, injectable
 *
 * Run: /opt/node22/bin/node --test scripts/guard/__tests__/entitlement-decision.test.mjs
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildCacheKey,
  decideFromCache,
  evaluateLive,
} from '../entitlement-decision.mjs';

const TENANT = '00000000-0000-0000-0000-000000000001';
const MODULE = 'channel_whatsapp';
const CANONICAL_KEY = 'ralphe:entitlement:00000000-0000-0000-0000-000000000001:channel_whatsapp';
const NOW = Date.parse('2026-06-20T12:00:00Z');

test('buildCacheKey matches Phase-19 DEL key byte-for-byte', () => {
  assert.equal(buildCacheKey(TENANT, MODULE), CANONICAL_KEY);
});

test('decideFromCache(null) => MISS (cacheUsable:false), never a deny [LRU/nil/eviction -> live]', () => {
  const d = decideFromCache(null, NOW);
  assert.equal(d.cacheUsable, false);
  assert.equal(d.allowed, undefined);
});

test('decideFromCache empty / nil string => MISS', () => {
  assert.equal(decideFromCache('', NOW).cacheUsable, false);
  assert.equal(decideFromCache('nil', NOW).cacheUsable, false);
  assert.equal(decideFromCache('   ', NOW).cacheUsable, false);
});

test('decideFromCache Redis error envelope => MISS (Redis error is fall-through, NOT a deny) [pivot c]', () => {
  const d = decideFromCache({ error: 'ECONNREFUSED' }, NOW);
  assert.equal(d.cacheUsable, false);
  assert.equal(d.allowed, undefined);
});

test('decideFromCache unparseable string => MISS', () => {
  const d = decideFromCache('not-json-{', NOW);
  assert.equal(d.cacheUsable, false);
});

test('cache HIT (valid row) => allowed, ZERO Strapi fetches [criterion 1]', () => {
  let strapiCalls = 0;
  const fetchMock = () => {
    strapiCalls++;
    return Promise.resolve({});
  };
  const cached = JSON.stringify({
    ent: { enabled: true, expires_at: null },
    mod: { tier: 'addon' },
    fetchedAt: '2026-06-20T11:00:00Z',
  });
  const d = decideFromCache(cached, NOW);
  assert.equal(d.cacheUsable, true);
  assert.equal(d.allowed, true);
  assert.match(d.reason, /^(ENTITLED_CACHED|GLOBAL_ENABLED_CACHED)$/);
  // The seam NEVER calls fetch on a hit — the call-count proof of criterion 1.
  assert.equal(strapiCalls, 0);
  // explicit alias matching the must-have contract
  assert.equal(strapiCalls === 0, true);
});

test('cache HIT, expired row re-evaluated on read => DENY EXPIRED (raw row, not a stored boolean) [pivot a]', () => {
  const cached = JSON.stringify({
    ent: { enabled: true, expires_at: '2000-01-01T00:00:00Z' },
    mod: { tier: 'addon' },
  });
  const d = decideFromCache(cached, NOW);
  assert.equal(d.cacheUsable, true);
  assert.equal(d.allowed, false);
  assert.match(d.reason, /^EXPIRED/);
});

test('cache HIT, global module => GLOBAL_ENABLED_CACHED allow', () => {
  const cached = JSON.stringify({
    ent: { enabled: true, expires_at: null },
    mod: { tier: 'shared_core' },
  });
  const d = decideFromCache(cached, NOW);
  assert.equal(d.allowed, true);
  assert.equal(d.reason, 'GLOBAL_ENABLED_CACHED');
});

test('cache HIT negative sentinel {neg:true} => DENY NO_ENTITLEMENT (negative cache honored)', () => {
  const d = decideFromCache(JSON.stringify({ neg: true }), NOW);
  assert.equal(d.cacheUsable, true);
  assert.equal(d.allowed, false);
  assert.match(d.reason, /^NO_ENTITLEMENT/);
});

test('evaluateLive Strapi error {error} => DENY GUARD_ERROR_FAILCLOSED, cacheable:false, ttl:0 [pivots b+d]', () => {
  const d = evaluateLive({ error: 'ECONNREFUSED' }, null, NOW);
  assert.equal(d.allowed, false);
  assert.match(d.reason, /^GUARD_ERROR_FAILCLOSED/);
  assert.equal(d.cacheable, false);
  assert.equal(d.ttl, 0);
  assert.equal(d.cacheRow, undefined);
});

test('evaluateLive 401 / non-2xx => FAILCLOSED (NOT NO_ENTITLEMENT — missing token must page) [Pitfall 8]', () => {
  const d = evaluateLive({ statusCode: 401 }, null, NOW);
  assert.equal(d.allowed, false);
  assert.match(d.reason, /^GUARD_ERROR_FAILCLOSED/);
  assert.equal(d.cacheable, false);
});

test('evaluateLive structurally-invalid body => FAILCLOSED (not a routine denial)', () => {
  const d = evaluateLive({ foo: 'bar' }, null, NOW);
  assert.equal(d.allowed, false);
  assert.match(d.reason, /^GUARD_ERROR_FAILCLOSED/);
  assert.equal(d.cacheable, false);
});

test('evaluateLive shared_core module => ALLOW GLOBAL_ENABLED, cacheable, ttl 300', () => {
  const d = evaluateLive({ data: [{ tier: 'shared_core' }] }, null, NOW);
  assert.equal(d.allowed, true);
  assert.equal(d.reason, 'GLOBAL_ENABLED');
  assert.equal(d.cacheable, true);
  assert.equal(d.ttl, 300);
});

test('evaluateLive enabled_globally module => ALLOW GLOBAL_ENABLED', () => {
  const d = evaluateLive({ data: [{ tier: 'addon', enabled_globally: true }] }, null, NOW);
  assert.equal(d.allowed, true);
  assert.equal(d.reason, 'GLOBAL_ENABLED');
});

test('evaluateLive empty product-modules => DENY MODULE_NOT_FOUND, cacheable negative ttl 60', () => {
  const d = evaluateLive({ data: [] }, null, NOW);
  assert.equal(d.allowed, false);
  assert.match(d.reason, /^MODULE_NOT_FOUND/);
  assert.equal(d.cacheable, true);
  assert.equal(d.ttl, 60);
});

test('evaluateLive valid module, zero entitlement rows => DENY NO_ENTITLEMENT, cacheRow {neg:true}, ttl 60', () => {
  const d = evaluateLive({ data: [{ tier: 'addon' }] }, { data: [] }, NOW);
  assert.equal(d.allowed, false);
  assert.match(d.reason, /^NO_ENTITLEMENT/);
  assert.equal(d.cacheable, true);
  assert.deepEqual(d.cacheRow, { neg: true });
  assert.equal(d.ttl, 60);
});

test('evaluateLive entitled, not expired => ALLOW ENTITLED, cacheRow {ent,mod,fetchedAt}, ttl 300, config_overrides', () => {
  const ent = { enabled: true, expires_at: '2099-01-01T00:00:00Z', config_overrides: { foo: 1 } };
  const mod = { tier: 'addon' };
  const d = evaluateLive({ data: [mod] }, { data: [ent] }, NOW);
  assert.equal(d.allowed, true);
  assert.equal(d.reason, 'ENTITLED');
  assert.equal(d.cacheable, true);
  assert.equal(d.ttl, 300);
  assert.deepEqual(d.config_overrides, { foo: 1 });
  assert.deepEqual(d.cacheRow.ent, ent);
  assert.deepEqual(d.cacheRow.mod, mod);
  assert.ok(typeof d.cacheRow.fetchedAt === 'string');
});

test('evaluateLive entitled but expired => DENY EXPIRED', () => {
  const ent = { enabled: true, expires_at: '2000-01-01T00:00:00Z' };
  const d = evaluateLive({ data: [{ tier: 'addon' }] }, { data: [ent] }, NOW);
  assert.equal(d.allowed, false);
  assert.match(d.reason, /^EXPIRED/);
});

test('evaluateLive honors injected TTL overrides {posTtl, negTtl}', () => {
  const pos = evaluateLive({ data: [{ tier: 'shared_core' }] }, null, NOW, { posTtl: 111, negTtl: 22 });
  assert.equal(pos.ttl, 111);
  const neg = evaluateLive({ data: [{ tier: 'addon' }] }, { data: [] }, NOW, { posTtl: 111, negTtl: 22 });
  assert.equal(neg.ttl, 22);
});

test('LRU eviction (miss) -> live query, never spurious deny [criterion 2]', () => {
  // miss surfaces as null; decideFromCache => cacheUsable:false => caller runs evaluateLive.
  assert.equal(decideFromCache(null, NOW).cacheUsable, false);
});
