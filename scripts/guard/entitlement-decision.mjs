/**
 * scripts/guard/entitlement-decision.mjs — Phase 20 (GRD-01)
 *
 * The PURE, n8n-free, Strapi-free decision seam for W0_MODULE_GUARD's Redis
 * cache-aside topology. It operates ONLY on its arguments (a cached raw value +
 * the two Strapi responses), so it is unit-testable with `node --test` and no
 * n8n / Strapi / Redis boot — proving "cache HIT → 0 Strapi fetches" as a
 * call-count assertion.
 *
 * Exports (plain ESM — NOT .ts, so no --experimental-strip-types is ever needed):
 *   buildCacheKey(tenant_id, module_key) -> string
 *   decideFromCache(cachedRaw, now)      -> { cacheUsable, allowed?, reason?, config_overrides? }
 *   evaluateLive(moduleRes, entRes, now, opts={}) -> { allowed, reason, config_overrides, cacheRow?, cacheable, ttl }
 *
 * The W0_MODULE_GUARD Code nodes carry an INLINED copy of this logic (n8n Code
 * nodes cannot `import` repo files); this seam is the single source of truth the
 * tests + the workflow mirror. Reason prefixes are byte-stable so 20-03's
 * classifier keys off them unchanged:
 *   GUARD_ERROR_FAILCLOSED | NO_ENTITLEMENT | MODULE_NOT_FOUND | EXPIRED | ENTITLED | GLOBAL_ENABLED
 *   (+ the _CACHED suffixes on the HIT path)
 *
 * Cache key is EXACTLY `ralphe:entitlement:${tenant_id}:${module_key}` —
 * byte-identical to the Phase-19 DEL side (audit-hook.ts:122) and ADR 0003.
 */

const DEFAULT_POS_TTL = 300; // ENTITLEMENT_CACHE_TTL_SEC default (positive)
const DEFAULT_NEG_TTL = 60; // ENTITLEMENT_NEG_CACHE_TTL_SEC default (negative)

/**
 * buildCacheKey — the single source of truth for the canonical key. The Redis
 * GET/SET node `key` expressions mirror this template byte-for-byte.
 */
export function buildCacheKey(tenant_id, module_key) {
  return `ralphe:entitlement:${tenant_id}:${module_key}`;
}

/**
 * Is `mod` a globally-enabled (no-entitlement-required) module?
 *   shared_core tier OR enabled_globally === true
 */
function isGlobalModule(mod) {
  return !!mod && (mod.tier === 'shared_core' || mod.enabled_globally === true);
}

/**
 * Re-evaluate an entitlement row's expiry against `now`.
 * Returns true when EXPIRED (expires_at present AND in the past).
 * Absent / null expires_at => never expires => false.
 */
function isExpired(ent, now) {
  if (!ent || ent.expires_at === undefined || ent.expires_at === null || ent.expires_at === '') {
    return false;
  }
  const exp = new Date(ent.expires_at).getTime();
  if (Number.isNaN(exp)) return false; // unparseable expiry => treat as non-expiring (live path re-fetches anyway)
  return exp < toEpoch(now);
}

/**
 * Coerce `now` (epoch ms number, Date, or ISO string) to epoch ms.
 */
function toEpoch(now) {
  if (now instanceof Date) return now.getTime();
  if (typeof now === 'number') return now;
  const t = new Date(now).getTime();
  return Number.isNaN(t) ? Date.now() : t;
}

/**
 * decideFromCache(cachedRaw, now)
 *
 * cachedRaw is whatever the Redis GET node surfaced:
 *   - null / '' / 'nil'                          -> MISS (cacheUsable:false) — fall through to live
 *   - a {error} envelope (continueOnFail)        -> MISS (cacheUsable:false) — Redis error is NOT a deny
 *   - an unparseable string                      -> MISS (cacheUsable:false)
 *   - JSON {neg:true}                            -> usable DENY, reason NO_ENTITLEMENT
 *   - JSON {ent,mod,fetchedAt}                   -> RE-EVALUATE expires_at vs now (raw row, NOT a stored boolean)
 *
 * NEVER returns a transient error as a usable hit; a MISS is NEVER a deny
 * (LRU eviction / nil => miss => live query).  [pivots a + c + criterion 2]
 */
export function decideFromCache(cachedRaw, now) {
  // 1) Normalize the "no usable value" cases -> MISS (fall through to Strapi).
  if (cachedRaw === null || cachedRaw === undefined) {
    return { cacheUsable: false };
  }

  let obj = cachedRaw;
  if (typeof cachedRaw === 'string') {
    const s = cachedRaw.trim();
    if (s === '' || s.toLowerCase() === 'nil' || s.toLowerCase() === 'null') {
      return { cacheUsable: false };
    }
    try {
      obj = JSON.parse(s);
    } catch {
      return { cacheUsable: false }; // unparseable -> miss, never a deny
    }
  }

  if (obj === null || typeof obj !== 'object') {
    return { cacheUsable: false };
  }

  // 2) A Redis continueOnFail error envelope -> miss (fall through to Strapi).
  if ('error' in obj) {
    return { cacheUsable: false };
  }

  // 3) Negative-cache sentinel -> usable DENY.
  if (obj.neg === true) {
    return {
      cacheUsable: true,
      allowed: false,
      reason: 'NO_ENTITLEMENT',
      config_overrides: {},
    };
  }

  // 4) A raw entitlement row {ent, mod, fetchedAt}: re-evaluate expiry on read.
  if (obj.ent && typeof obj.ent === 'object') {
    const ent = obj.ent;
    const mod = obj.mod || {};

    if (isExpired(ent, now)) {
      return {
        cacheUsable: true,
        allowed: false,
        reason: 'EXPIRED',
        config_overrides: {},
      };
    }

    const reason = isGlobalModule(mod) ? 'GLOBAL_ENABLED_CACHED' : 'ENTITLED_CACHED';
    return {
      cacheUsable: true,
      allowed: true,
      reason,
      config_overrides: ent.config_overrides || {},
    };
  }

  // 5) A global-module positive row cached without an entitlement row.
  if (obj.mod && isGlobalModule(obj.mod)) {
    return {
      cacheUsable: true,
      allowed: true,
      reason: 'GLOBAL_ENABLED_CACHED',
      config_overrides: {},
    };
  }

  // 6) Anything else parseable but not a recognized shape -> miss (never a deny).
  return { cacheUsable: false };
}

/**
 * Detect a Strapi httpRequest error/non-success envelope (Pitfall 8).
 * With continueOnFail:true a 401 (missing token) / 5xx / network error may
 * surface as {error}, a non-2xx statusCode, or a structurally-invalid body
 * rather than throwing. ALL of these mean "couldn't get a valid response" =>
 * GUARD_ERROR_FAILCLOSED (NOT NO_ENTITLEMENT — a missing token must PAGE).
 *
 * Returns a non-empty detail string when the response is an error; '' when OK.
 */
function strapiError(res) {
  if (res === null || res === undefined) return 'empty response';
  if (typeof res !== 'object') return 'non-object response';
  if ('error' in res && res.error) {
    const e = res.error;
    if (typeof e === 'string') return e;
    if (e && typeof e === 'object') return e.message || e.name || 'strapi error';
    return 'strapi error';
  }
  // non-2xx status surfaced by continueOnFail / fullResponse
  const status = res.statusCode ?? res.status;
  if (typeof status === 'number' && (status < 200 || status >= 300)) {
    return `HTTP ${status}`;
  }
  // structurally-invalid body: a valid Strapi list response has a `data` array.
  if (!('data' in res)) {
    return 'invalid body (no data field)';
  }
  if (!Array.isArray(res.data)) {
    return 'invalid body (data not an array)';
  }
  return '';
}

/**
 * evaluateLive(moduleRes, entRes, now, opts)
 *
 * moduleRes = Strapi product-modules response; entRes = tenant-entitlements
 * response (each possibly an httpRequest continueOnFail error envelope).
 *
 * opts = { posTtl, negTtl } — injectable TTLs (defaults 300 / 60), so the n8n
 * Evaluate node can pass $env.ENTITLEMENT_CACHE_TTL_SEC / ENTITLEMENT_NEG_CACHE_TTL_SEC.
 *
 * Decision ladder (§4):
 *   Strapi error (either call)      -> GUARD_ERROR_FAILCLOSED  (DENY, cacheable:false, ttl:0)  [pivots b + d]
 *   module not found (empty data[]) -> MODULE_NOT_FOUND         (DENY, cacheable, negTtl)
 *   shared_core / enabled_globally  -> GLOBAL_ENABLED           (ALLOW, cacheable, posTtl)
 *   no entitlement row              -> NO_ENTITLEMENT           (DENY, cacheRow {neg:true}, negTtl)
 *   entitlement expired             -> EXPIRED                  (DENY, cacheable, negTtl)
 *   entitled                        -> ENTITLED                 (ALLOW, cacheRow {ent,mod,fetchedAt}, posTtl)
 */
export function evaluateLive(moduleRes, entRes, now, opts = {}) {
  const posTtl = opts.posTtl ?? DEFAULT_POS_TTL;
  const negTtl = opts.negTtl ?? DEFAULT_NEG_TTL;

  // --- Strapi-error detection FIRST (Pitfall 8): fail closed, NEVER cache. ---
  const modErr = strapiError(moduleRes);
  if (modErr) {
    return {
      allowed: false,
      reason: `GUARD_ERROR_FAILCLOSED: product-modules ${modErr}`,
      config_overrides: {},
      cacheable: false,
      ttl: 0,
    };
  }

  const mod = moduleRes.data[0];

  // module not found => definitive negative.
  if (!mod) {
    return {
      allowed: false,
      reason: 'MODULE_NOT_FOUND',
      config_overrides: {},
      cacheRow: { neg: true },
      cacheable: true,
      ttl: negTtl,
    };
  }

  // shared_core / enabled_globally => allow without an entitlement row.
  if (isGlobalModule(mod)) {
    return {
      allowed: true,
      reason: 'GLOBAL_ENABLED',
      config_overrides: {},
      cacheRow: { mod, fetchedAt: new Date(toEpoch(now)).toISOString() },
      cacheable: true,
      ttl: posTtl,
    };
  }

  // Need a tenant entitlement — the second Strapi call must have succeeded.
  const entErr = strapiError(entRes);
  if (entErr) {
    return {
      allowed: false,
      reason: `GUARD_ERROR_FAILCLOSED: tenant-entitlements ${entErr}`,
      config_overrides: {},
      cacheable: false,
      ttl: 0,
    };
  }

  const ent = entRes.data[0];

  // no entitlement row => definitive negative (short TTL).
  if (!ent) {
    return {
      allowed: false,
      reason: 'NO_ENTITLEMENT',
      config_overrides: {},
      cacheRow: { neg: true },
      cacheable: true,
      ttl: negTtl,
    };
  }

  // expired entitlement => deny.
  if (isExpired(ent, now)) {
    return {
      allowed: false,
      reason: 'EXPIRED',
      config_overrides: {},
      cacheRow: { neg: true },
      cacheable: true,
      ttl: negTtl,
    };
  }

  // entitled — cache the RAW row + fetchedAt so expiry is re-evaluated on read.
  return {
    allowed: true,
    reason: 'ENTITLED',
    config_overrides: ent.config_overrides || {},
    cacheRow: { ent, mod, fetchedAt: new Date(toEpoch(now)).toISOString() },
    cacheable: true,
    ttl: posTtl,
  };
}
