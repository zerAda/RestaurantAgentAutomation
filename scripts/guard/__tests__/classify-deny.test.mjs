/**
 * node --test for scripts/guard/classify-deny.mjs (Phase 20 GRD-01 criterion 4).
 *
 * Proves: every stable reason prefix -> expected {severity, pageable, alertKey};
 * the core distinction GUARD_ERROR_FAILCLOSED (pageable) vs NO_ENTITLEMENT (not);
 * and an unknown / empty / null reason -> safe-default pageable HIGH.
 *
 * Run: /opt/node22/bin/node --test scripts/guard/__tests__/classify-deny.test.mjs
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { classify } from '../classify-deny.mjs';

test('GUARD_ERROR_FAILCLOSED -> cannot-determine, HIGH, pageable, GUARD_FAILCLOSED', () => {
  assert.deepEqual(classify('GUARD_ERROR_FAILCLOSED: ECONNREFUSED'), {
    class: 'cannot-determine',
    severity: 'HIGH',
    pageable: true,
    alertKey: 'GUARD_FAILCLOSED',
  });
});

test('NO_ENTITLEMENT -> denial, LOW, not paged', () => {
  const c = classify('NO_ENTITLEMENT: tenant=x module=channel_whatsapp');
  assert.equal(c.severity, 'LOW');
  assert.equal(c.pageable, false);
  assert.equal(c.class, 'denial');
  assert.equal(c.alertKey, null);
});

test('MODULE_NOT_FOUND -> LOW, not paged', () => {
  const c = classify('MODULE_NOT_FOUND: channel_whatsapp');
  assert.equal(c.severity, 'LOW');
  assert.equal(c.pageable, false);
});

test('EXPIRED -> LOW, not paged', () => {
  const c = classify('EXPIRED: tenant=x module=y expired=z');
  assert.equal(c.severity, 'LOW');
  assert.equal(c.pageable, false);
});

test('GUARD_ERROR: (input/caller error) -> caller-bug, MEDIUM, not paged', () => {
  const c = classify('GUARD_ERROR: tenant_id not provided (UNKNOWN_CHANNEL_IDENTITY)');
  assert.equal(c.class, 'caller-bug');
  assert.equal(c.severity, 'MEDIUM');
  assert.equal(c.pageable, false);
});

test('ENTITLED_CACHED / GLOBAL_ENABLED_CACHED -> allow, not paged', () => {
  assert.equal(classify('ENTITLED_CACHED').class, 'allow');
  assert.equal(classify('ENTITLED_CACHED').pageable, false);
  assert.equal(classify('GLOBAL_ENABLED_CACHED').class, 'allow');
  assert.equal(classify('GLOBAL_ENABLED_CACHED').pageable, false);
});

test('live positive reasons ENTITLED / GLOBAL_ENABLED -> allow', () => {
  assert.equal(classify('ENTITLED').class, 'allow');
  assert.equal(classify('GLOBAL_ENABLED').class, 'allow');
});

test('unknown reason -> safe default unknown, HIGH, pageable, GUARD_UNKNOWN (never swallow)', () => {
  assert.deepEqual(classify('SOME_BRAND_NEW_REASON'), {
    class: 'unknown',
    severity: 'HIGH',
    pageable: true,
    alertKey: 'GUARD_UNKNOWN',
  });
});

test('empty / null / undefined reason -> unknown pageable HIGH, no throw', () => {
  for (const v of ['', null, undefined]) {
    const c = classify(v);
    assert.equal(c.class, 'unknown');
    assert.equal(c.severity, 'HIGH');
    assert.equal(c.pageable, true);
  }
});

test('core distinction: FAILCLOSED is pageable AND NO_ENTITLEMENT is NOT [criterion 4]', () => {
  assert.equal(classify('GUARD_ERROR_FAILCLOSED: x').pageable, true);
  assert.equal(classify('NO_ENTITLEMENT: x').pageable, false);
});

test('FAILCLOSED is not shadowed by the generic GUARD_ERROR: caller-bug branch', () => {
  // a reason that starts GUARD_ERROR_FAILCLOSED must NOT be classified as caller-bug.
  const c = classify('GUARD_ERROR_FAILCLOSED: product-modules HTTP 401');
  assert.equal(c.class, 'cannot-determine');
  assert.equal(c.severity, 'HIGH');
  assert.equal(c.pageable, true);
});
