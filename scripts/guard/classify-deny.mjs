/**
 * scripts/guard/classify-deny.mjs — Phase 20 (GRD-01 criterion 4)
 *
 * A PURE, downstream reason-classifier that makes a GUARD_ERROR_FAILCLOSED
 * condition (cannot-determine: token missing / Strapi down) distinguishable from
 * a legitimate NO_ENTITLEMENT denial in alerting — so a missing/expired token
 * PAGES on-call rather than masquerading as a routine business denial.
 *
 * It keys off the guard's STABLE reason prefixes (emitted unchanged by
 * W0_MODULE_GUARD / entitlement-decision.mjs). This plan does NOT edit the guard
 * topology (O-3, downstream-only); the classification is consumed in the caller
 * deny-branch / W8_OPS alert path (see docs/guard-alert-split.md).
 *
 * Exports (pure ESM, ZERO n8n/Strapi imports):
 *   classify(reason) -> { class, severity: 'LOW'|'MEDIUM'|'HIGH', pageable: boolean, alertKey: string|null }
 *
 * Mapping (match by stable PREFIX; check FAILCLOSED before the generic GUARD_ERROR:):
 *   GUARD_ERROR_FAILCLOSED* -> cannot-determine, HIGH,   pageable, alertKey 'GUARD_FAILCLOSED'
 *   NO_ENTITLEMENT*         -> denial,           LOW,    not paged
 *   MODULE_NOT_FOUND*       -> denial,           LOW,    not paged
 *   EXPIRED*                -> denial,           LOW,    not paged
 *   GUARD_ERROR:            -> caller-bug,       MEDIUM, not paged   (input/caller error)
 *   ENTITLED_CACHED / GLOBAL_ENABLED_CACHED / ENTITLED / GLOBAL_ENABLED -> allow, LOW, not paged
 *   anything else / '' / null / undefined -> unknown, HIGH, pageable, alertKey 'GUARD_UNKNOWN'
 *     (SAFE DEFAULT: a new failure mode must NEVER be silently swallowed.)
 */

export function classify(reason) {
  const r = typeof reason === 'string' ? reason : '';

  // cannot-determine — MUST be checked before the generic GUARD_ERROR: so the
  // failclosed (pageable) case is not shadowed by the caller-bug (non-paged) case.
  if (r.startsWith('GUARD_ERROR_FAILCLOSED')) {
    return { class: 'cannot-determine', severity: 'HIGH', pageable: true, alertKey: 'GUARD_FAILCLOSED' };
  }

  // legitimate denials — normal business outcomes, not paged.
  if (r.startsWith('NO_ENTITLEMENT') || r.startsWith('MODULE_NOT_FOUND') || r.startsWith('EXPIRED')) {
    return { class: 'denial', severity: 'LOW', pageable: false, alertKey: null };
  }

  // input / caller error (tenant_id / module_key not provided) — not a token outage.
  if (r.startsWith('GUARD_ERROR:')) {
    return { class: 'caller-bug', severity: 'MEDIUM', pageable: false, alertKey: null };
  }

  // allow outcomes (cache-hit + live positive reasons) — tolerate as non-deny.
  if (
    r.startsWith('ENTITLED_CACHED') ||
    r.startsWith('GLOBAL_ENABLED_CACHED') ||
    r.startsWith('ENTITLED') ||
    r.startsWith('GLOBAL_ENABLED')
  ) {
    return { class: 'allow', severity: 'LOW', pageable: false, alertKey: null };
  }

  // SAFE DEFAULT: an unrecognized / empty reason pages so a new failure mode is surfaced.
  return { class: 'unknown', severity: 'HIGH', pageable: true, alertKey: 'GUARD_UNKNOWN' };
}
