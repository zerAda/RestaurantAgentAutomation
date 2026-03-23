# Phase 4: Test Coverage — Routing & Permissions - Research

**Researched:** 2026-03-23
**Domain:** nginx smoke testing, Strapi 5 permission integration testing, GitHub Actions path-filtered CI
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TEST-01 | Smoke test verifies each of the 8 nginx routing zones returns expected HTTP status (not 502/404) | Nginx zones mapped from nginx.conf; curl-based check pattern proven in existing scripts |
| TEST-02 | Smoke test verifies `Access-Control-Allow-Origin` appears exactly once on kiosk endpoints | `curl -I` response header inspection; `grep -c` for duplicate detection |
| TEST-03 | Rate limit smoke: 25 rapid requests to `/v1/inbound/whatsapp` confirms 429 fires after burst | meta_inbound zone: rate=10r/s burst=20 nodelay — 25 requests will trigger 429 after burst exhausted |
| TEST-04 | Nginx smoke tests run automatically in CI on every PR that touches `infra/gateway/nginx.conf` | GitHub Actions `paths:` filter on `infra/gateway/nginx.conf`; nginx runs in Docker in CI already |
| TEST-05 | Unauthenticated GET /api/products returns 200 with data (public role works) | Strapi Public role has product.find + findOne; kiosk uses gateway /v1/strapi/api/products |
| TEST-06 | Unauthenticated POST /api/orders returns 403 or 401 | Orders endpoint is NOT in Public role permissions; must confirm intended behavior |
| TEST-07 | Authenticated admin GET /api/orders returns full order data | Authenticated role has full CRUD on orders; JWT via POST /api/auth/local |
| TEST-08 | Permission tests run in CI against a local Strapi instance | Strapi 5 requires full Docker startup (~2-3 min in CI); test must run against containerized CMS |
</phase_requirements>

---

## Summary

Phase 4 adds the first automated test coverage for the two most fragile, zero-coverage surfaces: the nginx gateway routing rules and the Strapi permission matrix. Both surfaces have broken production before — nginx CORS header duplication and Strapi permission misconfiguration have caused real incidents recorded in session history.

The nginx smoke tests are fundamentally curl-based: spin up an nginx container with the production config, hit each of the 8 routing zones, and assert expected HTTP status codes and response headers. This approach is already proven in `scripts/smoke_security_gateway.sh` and the test harness. The key challenge is making these tests run in CI on PR paths that touch `infra/gateway/nginx.conf` specifically.

The Strapi permission tests require a live Strapi instance because permissions are enforced at the application layer (Strapi middleware), not nginx. Running Strapi in CI is feasible but requires a postgres service, proper env vars, and 2-3 minutes of startup time. The existing `docker-compose.test.yml` has postgres/redis but no CMS service — adding one is the main new infrastructure needed. The alternative is testing against the live VPS, which is simpler but fragile for CI (VPS state can drift).

**Primary recommendation:** Write bash-based smoke scripts following the established project pattern (`scripts/smoke-*.sh`). Add a dedicated `nginx-smoke` CI job with `paths:` filter for `infra/gateway/nginx.conf`. Add a `strapi-permissions` CI job that spins up a minimal Strapi using `ghcr.io/zerada/resto-bot-cms:latest` with postgres.

---

## Nginx Routing Zone Inventory

From `infra/gateway/nginx.conf` — the 8 routing zones that TEST-01 must cover:

| Zone # | Path | Method(s) | Expected Status | Proxy Target | Notes |
|--------|------|-----------|-----------------|--------------|-------|
| 1 | `/healthz` | GET | 200 | nginx static | Returns "ok" |
| 2 | `/v1/inbound/whatsapp` | GET | 200 or upstream | n8n webhook | Meta verify; n8n may return 404 if workflow inactive |
| 3 | `/v1/inbound/whatsapp` | POST + JSON | 200 or upstream | n8n webhook | Rate zone: meta_inbound burst=20 |
| 4 | `/v1/inbound/instagram` | GET/POST | 200 or upstream | n8n webhook | Same as WA pattern |
| 5 | `/v1/inbound/messenger` | GET/POST | 200 or upstream | n8n webhook | Same as WA pattern |
| 6 | `/v1/customer/` | GET/POST | proxied | n8n webhook | internal_token zone burst=50 |
| 7 | `/v1/admin/` | GET/POST | proxied | n8n webhook | internal_token zone burst=50 |
| 8 | `/v1/strapi/` | GET | proxied | cms:1337 | kiosk_menu zone; CORS headers stripped + re-added |

**Note:** `/v1/strapi/api/orders` (POST only) and `/v1/portal/` (full CRUD) are additional specialized zones. The 8 zones above cover the main categories. The smoke test should check that no zone returns 502 (upstream down) or 404 (route missing).

**What constitutes "expected status" for upstream-proxied zones:**
- `/healthz` → exactly 200
- `/v1/inbound/*` → NOT 502, NOT 404. Acceptable: 200, 401, 403 (n8n present but workflow may be inactive in CI = 404 from n8n is acceptable, so the test must be "not 502 from nginx itself")
- `/v1/strapi/*` → NOT 502 (CMS healthy), acceptable: 200 or 401 if no token
- `/v1/admin/`, `/v1/customer/`, `/v1/internal/` → NOT 502, NOT nginx-level 404

**Critical insight:** In CI without live n8n, inbound zones will return 502 unless n8n is running. The nginx smoke test scope should be limited to what can run in a lightweight CI container — nginx-only tests (static routes + CORS headers + rate limiting) are testable without a live upstream. For route reachability (not 502), n8n must be available.

---

## Standard Stack

### Core
| Library/Tool | Version | Purpose | Why Standard |
|---|---|---|---|
| nginx:1.27-alpine | 1.27-alpine (pinned in compose) | Container for smoke testing nginx.conf | Already used in test harness; matches production image |
| curl | system (ubuntu-latest) | HTTP requests in smoke scripts | All existing scripts use curl; available in all CI runners |
| bash | system | Script language for smoke tests | All existing scripts are bash; project convention |
| docker compose | v2 (ubuntu-latest) | Spin up nginx + optional CMS in CI | Already used in test harness and integration tests |

### Supporting
| Library/Tool | Version | Purpose | When to Use |
|---|---|---|---|
| jq | system (ubuntu-latest) | Parse JSON responses | Already used in test harness and smoke-cms-routes.sh |
| python3 | 3.11 (ci.yml env) | Fallback JSON parsing when jq unavailable | Fallback in existing scripts |
| ghcr.io/zerada/resto-bot-cms | latest | Strapi instance for permission tests | Built on main branch; available in GHCR |
| postgres:15-alpine | 15-alpine | Strapi requires postgres backing | Matches production DB version |

### What NOT to Use
- Jest, pytest, bats — the project uses bash scripts for smoke tests exclusively; no test framework is needed for curl-based HTTP checks
- nginx test mode (nginx -t) — only validates config syntax, does not test routing behavior
- Mock HTTP servers — not needed; nginx routes to real services or returns static responses

---

## Architecture Patterns

### Recommended Project Structure

```
scripts/
├── smoke-nginx-routing.sh       # TEST-01, TEST-02, TEST-03 (new)
├── smoke-strapi-permissions.sh  # TEST-05, TEST-06, TEST-07 (new)
├── smoke-cms-routes.sh          # existing (Phase 1)
├── smoke-post-rebuild.sh        # existing (Phase 1)
└── smoke_security_gateway.sh    # existing (security tests)

.github/workflows/
├── ci.yml                       # existing — add nginx-smoke job + strapi-permissions job
└── (no new workflow file needed — extend existing ci.yml)

infra/gateway/
├── nginx.conf                   # production (unchanged)
└── nginx.test.conf              # test config (already exists, needs strapi section added)

docker/
├── docker-compose.test.yml      # existing — add cms service for permission tests
└── docker-compose.yml           # existing
```

### Pattern 1: Nginx Smoke Test in CI Without Live Upstreams

**What:** Run nginx in Docker with the production nginx.conf, point all upstream addresses to a dummy stub or `localhost:9999` (nothing listening). Test nginx-layer behavior (routes exist, not 404; headers correct; rate limits fire) without needing live n8n or CMS.

**When to use:** TEST-01 (zone reachability), TEST-02 (CORS header deduplication), TEST-03 (rate limiting). These are all nginx-layer behaviors that don't require the upstream to respond.

**How nginx responds when upstream is down:**
- If upstream connection refused: nginx returns 502
- TEST-01 "zones return expected status (not 502)" means the upstream MUST be available
- Alternative: use `return 200` stub upstreams for the nginx smoke test — this tests routing config, not upstream health

**Resolution:** Use a two-mode approach:
1. **Config-only test (CI):** Replace upstream proxy_pass with stub `return 200` via a test overlay config. This tests that route definitions, CORS headers, and security rules are correct WITHOUT requiring n8n or CMS to be running. Fast (< 30 seconds).
2. **Full routing test (VPS):** `smoke_security_gateway.sh` and `smoke-post-rebuild.sh` hit the live VPS. These are manual/deployment smoke tests.

**Practical nginx.conf test override pattern:**
```bash
# In CI: create a minimal override that stubs all upstreams
# Write nginx.smoke.conf that replaces proxy_pass lines with return 200
# Mount as /etc/nginx/conf.d/default.conf in nginx:1.27-alpine container
docker run --rm -d --name nginx-smoke \
  -v $(pwd)/infra/gateway/nginx.smoke.conf:/etc/nginx/conf.d/default.conf:ro \
  -p 18090:8080 nginx:1.27-alpine
```

### Pattern 2: Rate Limit Test Against Real nginx

**What:** Spin up nginx with production config, point n8n upstream to a stub that always returns 200, then send 25 rapid requests and assert 429 fires.

**nginx rate limit config (from nginx.conf):**
```nginx
limit_req_zone $binary_remote_addr zone=meta_inbound:10m rate=10r/s;
# ...
limit_req zone=meta_inbound burst=20 nodelay;
```

**Math:** rate=10r/s, burst=20, nodelay. At burst=20, first 20 requests are served immediately. Request 21+ are rejected with 429 immediately (nodelay). Sending 25 rapid requests will produce 429 starting at request 21.

**Test pattern:**
```bash
THROTTLED=0
for i in $(seq 1 25); do
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST http://localhost:18090/v1/inbound/whatsapp \
    -H "Content-Type: application/json" \
    -d '{"msg_id":"rate-test-'$i'"}')
  [ "$status" = "429" ] && THROTTLED=$((THROTTLED + 1))
done
# Assert THROTTLED >= 1 (at least one 429 received)
```

**Critical:** The `$binary_remote_addr` key means all requests from the same IP share one bucket. In CI, all curl requests originate from `127.0.0.1` (same bucket) — this is correct behavior for the test.

### Pattern 3: CORS Header Deduplication Test

**What:** Verify `Access-Control-Allow-Origin` appears exactly once on kiosk endpoints.

**Why this matters (from nginx.conf):** The production config uses `proxy_hide_header Access-Control-Allow-Origin` + `add_header Access-Control-Allow-Origin ... always`. Without `proxy_hide_header`, Strapi's own ACAO header plus nginx's added header = two ACAO headers = browser CORS failure.

**Test pattern:**
```bash
# Count occurrences of ACAO header
ACAO_COUNT=$(curl -sI http://localhost:18090/v1/strapi/api/products \
  | grep -ic "access-control-allow-origin")
[ "$ACAO_COUNT" -eq 1 ] || fail "ACAO appears $ACAO_COUNT times (expected 1)"
```

**In CI with stub upstream:** The stub returns no headers, so nginx's `add_header` adds exactly one. This tests the nginx config is correct. Does NOT test that Strapi's headers are being hidden (that requires a live Strapi). **Decision for planner:** TEST-02 in CI can be validated with stub upstream (confirms nginx adds exactly one). VPS test would confirm Strapi's headers are also hidden.

### Pattern 4: Strapi Permission Tests Against Containerized CMS

**What:** Start a `ghcr.io/zerada/resto-bot-cms:latest` container backed by postgres, wait for `/_health` to return 204, then run permission assertions.

**Challenges:**
1. Strapi first-boot migrations take ~2-3 minutes (81 tables created from scratch)
2. CI timeout must be at least 10 minutes for the strapi-permissions job
3. The GHCR image is only built on main branch (`docker-build` job is `if: github.ref == 'refs/heads/main'`) — on PRs, the image may not be updated
4. Strapi needs env vars: `APP_KEYS`, `API_TOKEN_SALT`, `ADMIN_JWT_SECRET`, `JWT_SECRET`, `DATABASE_*`

**Alternative (simpler for PRs):** Run permission tests against the live VPS only (no CI container startup). This is already done by `smoke-cms-routes.sh`. However, TEST-08 explicitly says "run in CI against a local Strapi instance."

**Practical CI approach for TEST-08:**
- Add a `strapi-permissions` job in ci.yml gated on `paths: ['inventory-cms/**', '.github/workflows/strapi-permissions.yml']`
- Only runs on main/release (where CMS image exists in GHCR)
- On PRs not touching CMS: skip (already passes since no changes)
- Use `docker run` with the GHCR image, not docker-compose (simpler for CI)

**Strapi auth flow for tests:**
```bash
# Get JWT for authenticated tests (from smoke-cms-routes.sh pattern)
AUTH=$(curl -s -X POST http://localhost:1337/api/auth/local \
  -H 'Content-Type: application/json' \
  -d '{"identifier":"adel.zeriri@gmail.com","password":"RestoBot2026"}')
TOKEN=$(echo "$AUTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('jwt',''))")
```

### Anti-Patterns to Avoid

- **Testing at Traefik/VPS level for CI:** CI has no VPS access; tests must be container-local
- **Using nginx -t as a "routing test":** Only validates config syntax, not actual routing behavior
- **Skipping stub upstream for nginx CI:** Without stubs, ALL proxy_pass routes return 502 — tests are useless
- **Assuming GHCR image is current on PRs:** CMS image is only built on main; don't require it for PR CI
- **Setting burst test > burst limit in nginx.conf:** burst=20 means requests 1-20 pass. Request 21 gets 429. Test with 25 requests is correct.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON body parsing in bash | Custom awk/sed JSON parsing | `jq` (already in harness) or `python3 -c "import json,sys; ..."` | Already proven in smoke-cms-routes.sh; edge cases handled |
| Rate limit verification math | Complex timing logic | Simple loop of N requests counting 429s | nginx `nodelay` makes timing irrelevant — 429 fires immediately at burst exhaustion |
| Strapi JWT authentication | Custom auth flow | Copy pattern from smoke-cms-routes.sh | Already handles jq/python3 fallback; proven against production |
| CORS header count | Custom header parser | `grep -ic "access-control-allow-origin"` on curl -I output | Headers are case-insensitive in HTTP; -i flag handles this |
| CI nginx container startup | Custom entrypoint script | `docker run -d nginx:1.27-alpine ...` then `sleep 1` | nginx starts instantly from alpine image |

**Key insight:** Everything needed for Phase 4 tests can be built with curl + bash + grep/jq. No new dependencies, no test frameworks. The project pattern is explicit: bash smoke scripts.

---

## Common Pitfalls

### Pitfall 1: nginx 502 vs. Actual Route Missing
**What goes wrong:** Test sees 502 and reports "route broken" but it's actually "upstream not running."
**Why it happens:** In CI, n8n or CMS are not started; nginx correctly returns 502 (upstream connection refused). The test cannot distinguish "route doesn't exist" (404) from "route exists but upstream down" (502).
**How to avoid:** Use a stub upstream config for CI nginx routing tests. A stub nginx.smoke.conf replaces all `proxy_pass` directives with `return 200 '{"ok":true}'`. This tests routing rules without needing live upstreams.
**Warning signs:** All inbound routes return 502 in CI; healthz returns 200.

### Pitfall 2: Rate Limit Test Flakiness Due to nginx Zone Persistence
**What goes wrong:** If the same nginx container is reused between tests, the rate limit zone `meta_inbound` may carry state from previous requests, causing 429 to fire earlier than expected.
**Why it happens:** nginx rate limit zones are in-memory shared memory segments that persist for the container lifetime.
**How to avoid:** Start a fresh nginx container for each rate limit test run (`docker rm -f nginx-smoke` before starting). Or include a delay between test groups to let the zone expire.
**Warning signs:** Rate limit test fails on second run in same CI job.

### Pitfall 3: CORS Test Passes With Stub But Fails on VPS
**What goes wrong:** Stub upstream returns no headers, so nginx adds exactly one ACAO. But on VPS, Strapi returns its own ACAO and nginx fails to strip it.
**Why it happens:** The `proxy_hide_header` directive requires the upstream to actually send the header for the hide to have effect. With a stub, there's nothing to hide.
**How to avoid:** Accept that CI tests ACAO count with stub (validates nginx config adds one). Add a VPS-targeted ACAO test in `smoke-post-rebuild.sh` that checks via the live gateway.
**Warning signs:** CI passes but ACAO appears twice when tested against VPS.

### Pitfall 4: Strapi Permission Test Brittleness From DB State
**What goes wrong:** The `adel.zeriri@gmail.com` user or role/permission rows don't exist in the fresh CI Strapi DB, causing auth to fail.
**Why it happens:** Strapi permissions are stored in postgres, not in the image/code. A fresh DB has no users or permissions by default.
**How to avoid:** The permission smoke test must either (a) create test users/roles via Strapi admin API before testing, or (b) use Strapi API tokens (configured via env vars at startup) instead of user JWT. API tokens bypass role-based permissions and are created deterministically.
**Better approach:** Use Strapi's API token for authenticated tests. Set `STRAPI_API_TOKEN` as a CI secret. For unauthenticated tests, just hit the API without a token — Public role is seeded by Strapi's built-in bootstrap.
**Warning signs:** All Strapi permission tests fail with 401 even for public endpoints.

### Pitfall 5: Strapi Public Role Permissions Are Not Seeded
**What goes wrong:** On a fresh Strapi instance, the Public role has zero permissions by default. `GET /api/products` returns 403 instead of 200.
**Why it happens:** Strapi doesn't auto-grant Public role permissions to any content type — it must be done via admin UI or API.
**How to avoid:** Include a `wait-and-seed.sh` step in the CI job that hits the Strapi admin API after startup to grant `product.find` and `product.findOne` to the Public role. The admin API endpoint is: `PUT /admin/roles/:roleId/permissions` with Strapi admin JWT.
**Alternatively:** Accept that the "Strapi permission test" validates the INTENT (Public role should have product.find) by asserting it via API rather than testing the live permission. This is not a useful integration test.
**Recommended:** The smoke script must seed permissions as part of setup. This is a test setup concern, not a production concern.
**Warning signs:** `GET /api/products` returns 403 on fresh CI Strapi instance.

### Pitfall 6: Content-Type Header Required for nginx POST Routes
**What goes wrong:** POST to `/v1/inbound/whatsapp` without `Content-Type: application/json` returns 415, not 200/proxied.
**Why it happens:** nginx.conf has a content-type check: `if ($content_type_ok = 0) { return 415 }`.
**How to avoid:** Always include `-H "Content-Type: application/json"` in smoke test POST requests to inbound endpoints.
**Warning signs:** Rate limit test sends 25 requests but gets 415 for all, so no 429 is observed.

---

## Code Examples

### Nginx Routing Smoke Test (curl pattern)

```bash
# Source: infra/gateway/nginx.conf analysis + scripts/smoke_security_gateway.sh pattern

# Zone 1: /healthz (static, no upstream needed)
status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:18090/healthz)
[ "$status" = "200" ] || fail "healthz: got $status, expected 200"

# Zone 3: /v1/inbound/whatsapp POST (with stub upstream in CI)
status=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:18090/v1/inbound/whatsapp \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"smoke-1"}')
[ "$status" != "404" ] || fail "inbound/whatsapp route missing (404)"
[ "$status" != "502" ] || fail "inbound/whatsapp upstream down (502)"

# Zone 8: /v1/strapi/ CORS check
ACAO_COUNT=$(curl -sI http://localhost:18090/v1/strapi/api/products \
  | grep -ic "^access-control-allow-origin:")
[ "$ACAO_COUNT" -eq 1 ] || fail "ACAO appears ${ACAO_COUNT}x on kiosk endpoint (expected 1)"
```

### Rate Limit Test Pattern

```bash
# Source: nginx.conf — meta_inbound: rate=10r/s burst=20 nodelay
# 25 requests from same IP: first 20 pass (burst), requests 21-25 get 429

THROTTLED=0
PASS_COUNT=0
for i in $(seq 1 25); do
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST http://localhost:18090/v1/inbound/whatsapp \
    -H "Content-Type: application/json" \
    -d "{\"msg_id\":\"rl-$i\"}")
  if [ "$status" = "429" ]; then
    THROTTLED=$((THROTTLED + 1))
  else
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
done

echo "Pass: ${PASS_COUNT}, Throttled: ${THROTTLED}"
[ "$THROTTLED" -ge 1 ] || fail "Rate limit did not fire (got 0 throttled in 25 requests)"
# Expect roughly 5 throttled (requests 21-25), but accept >= 1
```

### Strapi Permission Test Pattern

```bash
# Source: scripts/smoke-cms-routes.sh pattern

CMS_URL="${CMS_URL:-http://localhost:1337}"

# TEST-05: Unauthenticated GET /api/products -> 200
status=$(curl -s -o /tmp/products.json -w "%{http_code}" "${CMS_URL}/api/products")
[ "$status" = "200" ] || fail "GET /api/products unauthenticated: got $status (expected 200)"
grep -q '"data"' /tmp/products.json || fail "GET /api/products: no data array in response"

# TEST-06: Unauthenticated POST /api/orders -> 403 or 401
status=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${CMS_URL}/api/orders" \
  -H "Content-Type: application/json" \
  -d '{"data":{"status":"new"}}')
[[ "$status" = "403" || "$status" = "401" ]] || \
  fail "POST /api/orders unauthenticated: got $status (expected 403 or 401)"

# TEST-07: Authenticated admin GET /api/orders -> 200
AUTH=$(curl -s -X POST "${CMS_URL}/api/auth/local" \
  -H 'Content-Type: application/json' \
  -d "{\"identifier\":\"${STRAPI_EMAIL}\",\"password\":\"${STRAPI_PASSWORD}\"}")
if command -v jq >/dev/null 2>&1; then
  TOKEN=$(echo "$AUTH" | jq -r '.jwt // empty')
else
  TOKEN=$(echo "$AUTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('jwt',''))" 2>/dev/null || echo "")
fi
[ -n "$TOKEN" ] || fail "Could not obtain JWT for admin user"

status=$(curl -s -o /tmp/orders.json -w "%{http_code}" \
  -H "Authorization: Bearer ${TOKEN}" \
  "${CMS_URL}/api/orders")
[ "$status" = "200" ] || fail "GET /api/orders authenticated: got $status (expected 200)"
grep -q '"data"' /tmp/orders.json || fail "GET /api/orders: no data array in response"
```

### GitHub Actions Path Filter Pattern

```yaml
# Source: GitHub Actions docs — paths filter for CI jobs
# Pattern: Add a new job to ci.yml that only runs when nginx.conf changes

nginx-smoke:
  name: Nginx Routing Smoke
  runs-on: ubuntu-latest
  needs: [integrity-gate]
  # Only run on PRs/pushes that touch the nginx config
  if: |
    contains(github.event.head_commit.modified, 'infra/gateway/nginx.conf') ||
    github.event_name == 'workflow_dispatch'
  timeout-minutes: 5
  steps:
    - uses: actions/checkout@...
    - name: Run nginx routing smoke
      run: bash scripts/smoke-nginx-routing.sh
```

**Better approach — use `paths:` at the `on:` trigger level per workflow file:**
The current `ci.yml` triggers on all PRs. Adding a `paths:` filter to a single job via `if:` condition requires checking `github.event.head_commit.modified` which is unreliable. The correct approach is either:
1. A separate `nginx-smoke.yml` workflow with `on: pull_request: paths: ['infra/gateway/nginx.conf']`
2. Or always run the nginx smoke test as part of ci.yml (it runs in < 30 seconds)

**Recommended:** Always run the nginx smoke in ci.yml (fast) + add a separate `nginx-smoke.yml` that triggers specifically on `infra/gateway/**` changes. The always-run option ensures it's never skipped accidentally.

### Nginx Stub Config for CI Testing

```nginx
# infra/gateway/nginx.smoke.conf — CI-only config
# Replace all proxy_pass with static responses so routing tests work without upstreams

upstream n8n_upstream { server 127.0.0.1:19999; }  # nothing listening — will 502

server {
  listen 8080;
  server_tokens off;

  # Real-IP and rate zones from production
  limit_req_zone $binary_remote_addr zone=meta_inbound:10m rate=10r/s;
  limit_req_zone $http_x_api_token zone=internal_token:10m rate=20r/s;
  limit_conn_zone $binary_remote_addr zone=conn_per_ip:10m;
  limit_req_zone $binary_remote_addr zone=kiosk_menu:10m rate=30r/s;

  # Security headers (same as production)
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-Frame-Options "DENY" always;

  location = /healthz {
    add_header Content-Type text/plain;
    return 200 'ok';
  }

  location = /v1/inbound/whatsapp {
    limit_except GET POST { deny all; }
    set $content_type_ok 1;
    if ($request_method = POST) { set $content_type_ok 0; }
    if ($http_content_type ~* "application/json") { set $content_type_ok 1; }
    if ($content_type_ok = 0) { return 415 '{"error":"unsupported_media_type"}'; }
    limit_req zone=meta_inbound burst=20 nodelay;
    return 200 '{"ok":true,"stub":true}';
  }
  # ... etc
}
```

---

## CI Integration Architecture

### New CI Job: nginx-smoke

**Location:** Add to existing `ci.yml`

**Trigger strategy:** Run on every PR (fast, < 30 seconds). The job is cheap enough that conditional execution is not worth the complexity.

**What it tests:**
- Zone 1: `/healthz` returns 200
- Zone 2/3: `/v1/inbound/whatsapp` GET/POST do not return nginx-level 404 (route exists)
- Zone 4/5: Same for instagram, messenger
- Zone 6/7: `/v1/customer/`, `/v1/admin/` do not return nginx-level 404
- Zone 8: `/v1/strapi/` has `Access-Control-Allow-Origin` exactly once (TEST-02)
- Rate limit: 25 POSTs to `/v1/inbound/whatsapp` triggers 429 (TEST-03)
- Security: `?token=` query params return 401 (already in smoke_security_gateway.sh)

**Infrastructure required:**
- A smoke-compatible nginx.conf variant that returns 200 for all locations (no proxy_pass needed for header/rate-limit tests)
- OR: spin up nginx:1.27-alpine with a stub upstream (node -e "require('http').createServer((_,r)=>{r.end('ok')}).listen(9999)")

### New CI Job: strapi-permissions

**Location:** Add to existing `ci.yml` OR new `strapi-permissions.yml`

**Trigger strategy:** Run on PRs that touch `inventory-cms/**` or push to main. On other PRs, skip (no CMS changes = no permission regression risk).

**Timeout:** 10 minutes minimum (Strapi first-boot takes 2-3 minutes in CI)

**Services required:**
- `postgres:15-alpine` with env `POSTGRES_DB=strapi`
- CMS container: `ghcr.io/zerada/resto-bot-cms:latest` or built from `./inventory-cms`

**Env vars required (as CI secrets):**
- `STRAPI_APP_KEYS` (required for Strapi startup)
- `STRAPI_ADMIN_JWT_SECRET`
- `STRAPI_JWT_SECRET`
- `STRAPI_API_TOKEN_SALT`
- `STRAPI_EMAIL` and `STRAPI_PASSWORD` (for TEST-07 authenticated tests)

**Seeding Public role permissions:**
After Strapi starts, use the admin API to grant `product.find`/`product.findOne` to Public role:
```bash
# Get admin JWT
ADMIN_JWT=$(curl -s -X POST http://localhost:1337/admin/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"...","password":"..."}' | jq -r '.data.token')

# Grant Public role permissions via admin API
# (Strapi 5 admin API endpoint for permissions)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| Test nginx routes by hitting VPS manually | Automated CI smoke tests with stub configs | Phase 4 | Regressions caught before merge |
| Strapi permissions verified manually in admin UI | Automated curl-based permission assertions | Phase 4 | Permission matrix is regression-tested |
| Rate limit test: manual burst testing | Automated 25-request loop asserting 429 | Phase 4 | Rate limit config changes are validated |
| nginx.test.conf (exists, very minimal) | Extended nginx.smoke.conf with all zones + security rules | Phase 4 | CI config matches production more closely |

**Current nginx.test.conf gap:** The existing `infra/gateway/nginx.test.conf` is very minimal — it omits all security rules, rate limits, and CORS headers. It is a passthrough-only test config. A new `nginx.smoke.conf` is needed that includes the security rules for TEST-02 and TEST-03.

---

## Validation Architecture

### Test Framework

| Property | Value |
|---|---|
| Framework | bash scripts (no external framework) |
| Config file | none — scripts are self-contained |
| Quick run command | `bash scripts/smoke-nginx-routing.sh` |
| Full suite command | `bash scripts/smoke-nginx-routing.sh && bash scripts/smoke-strapi-permissions.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | Infra Required |
|--------|----------|-----------|-------------------|----------------|
| TEST-01 | 8 nginx zones return expected status | smoke (nginx container) | `bash scripts/smoke-nginx-routing.sh` | nginx:1.27-alpine + stub upstream |
| TEST-02 | ACAO appears exactly once on kiosk endpoints | smoke (nginx container) | `bash scripts/smoke-nginx-routing.sh` (included) | nginx:1.27-alpine + stub upstream |
| TEST-03 | 25 rapid requests trigger 429 | smoke (nginx container) | `bash scripts/smoke-nginx-routing.sh` (included) | nginx:1.27-alpine (rate zones active) |
| TEST-04 | Nginx smoke runs in CI on nginx.conf PRs | CI wiring | ci.yml `nginx-smoke` job | GitHub Actions path filter |
| TEST-05 | Unauth GET /api/products → 200 + data | integration | `bash scripts/smoke-strapi-permissions.sh` | Strapi container + postgres |
| TEST-06 | Unauth POST /api/orders → 403/401 | integration | `bash scripts/smoke-strapi-permissions.sh` (included) | Strapi container + postgres |
| TEST-07 | Auth admin GET /api/orders → 200 + data | integration | `bash scripts/smoke-strapi-permissions.sh` (included) | Strapi container + postgres |
| TEST-08 | Strapi permission tests run in CI | CI wiring | ci.yml `strapi-permissions` job | GHCR CMS image + postgres CI service |

### Sampling Rate

- **Per task commit:** `bash scripts/smoke-nginx-routing.sh` (< 30s, nginx-only)
- **Per wave merge:** `bash scripts/smoke-nginx-routing.sh && bash scripts/smoke-strapi-permissions.sh` (< 5 min)
- **Phase gate:** Full suite green + CI jobs green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `scripts/smoke-nginx-routing.sh` — covers TEST-01, TEST-02, TEST-03
- [ ] `scripts/smoke-strapi-permissions.sh` — covers TEST-05, TEST-06, TEST-07
- [ ] `infra/gateway/nginx.smoke.conf` — CI-suitable nginx config with stubs + security rules intact
- [ ] CI job `nginx-smoke` in `.github/workflows/ci.yml` — covers TEST-04
- [ ] CI job `strapi-permissions` in `.github/workflows/ci.yml` — covers TEST-08

---

## Open Questions

1. **TEST-06 intended behavior: does unauthenticated POST /api/orders return 403 or 401?**
   - What we know: MEMORY.md notes "Strapi strapiClient: 401 = auto-logout, 403 = just error." The Authenticated role has order creation permissions. The Public role has product.find/findOne only — no order write permissions.
   - What's unclear: Does Strapi 5 return 401 (unauthenticated = no token) or 403 (authenticated but insufficient permissions) for a POST with no token?
   - Strapi 5 behavior: no token = treated as Public role. Public role has no order create permission = 403 Forbidden (not 401 Unauthorized, which would imply authentication failure).
   - Recommendation: Test should accept EITHER 401 OR 403 (as REQUIREMENTS.md already allows both). The test is valid either way.
   - Confidence: MEDIUM — based on Strapi 5 permission model from MEMORY.md, but should be verified on first run.

2. **Strapi permission seeding in CI: admin API vs. env-based bootstrap**
   - What we know: Strapi 5 does not auto-seed Public role permissions for content types. Permissions must be set via admin API or database seed.
   - What's unclear: Does Strapi 5 support environment-variable-based permission seeding, or is a DB seed script required?
   - Recommendation: Write a seed step in `smoke-strapi-permissions.sh` that uses the Strapi admin API to grant permissions after startup. This is the most robust approach (no DB direct access needed).
   - Confidence: HIGH for the approach; LOW for specific Strapi 5 admin API endpoint format (needs verification on first run).

3. **nginx.smoke.conf vs. extending nginx.test.conf**
   - What we know: `nginx.test.conf` is very minimal (no rate limits, no CORS, no security headers). TEST-02 (CORS) and TEST-03 (rate limit) require those sections.
   - What's unclear: Should we create a new `nginx.smoke.conf` or extend `nginx.test.conf`?
   - Recommendation: Create a new `nginx.smoke.conf` that includes all production security rules but replaces `proxy_pass` with `return 200 '{"ok":true}'` stubs. Keep `nginx.test.conf` for the full test harness (which has live n8n).
   - Confidence: HIGH — clean separation of concerns.

---

## Sources

### Primary (HIGH confidence)

- `infra/gateway/nginx.conf` — complete production nginx config; all 8 zones mapped directly
- `scripts/smoke_security_gateway.sh` — existing gateway smoke pattern (curl-based)
- `scripts/smoke-cms-routes.sh` — existing CMS auth + route check pattern
- `scripts/smoke-post-rebuild.sh` — multi-check smoke pattern with pass/fail counters
- `.github/workflows/ci.yml` — full CI pipeline structure; job dependency graph
- `docker/docker-compose.test.yml` — test infrastructure (postgres, redis, n8n, gateway, mock-api)
- `infra/gateway/nginx.test.conf` — existing minimal test nginx config
- `.planning/REQUIREMENTS.md` — TEST-01 through TEST-08 definitions
- MEMORY.md — Strapi permission model, role/permission table names, auth behavior

### Secondary (MEDIUM confidence)

- nginx documentation (rate limiting behavior): `limit_req burst=20 nodelay` fires 429 immediately at burst exhaustion — verified by existing `smoke_security_gateway.sh` which already tests this behavior pattern
- Strapi 5 permission model (from MEMORY.md): Public role = unauthenticated requests; Authenticated role = users with valid JWT; permissions stored in `up_permissions` + `up_permissions_role_lnk`

### Tertiary (LOW confidence)

- Strapi 5 admin API endpoint for granting permissions: exact format not verified against live instance; needs confirmation on first run

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — all tools already in use (curl, bash, docker); no new dependencies
- Architecture: HIGH — nginx zone mapping from direct conf inspection; CI patterns from existing workflows
- Pitfalls: HIGH — CORS duplication, rate limit zone persistence, and permission seeding are real issues observed in project history
- Strapi permission seeding: MEDIUM — approach is sound, exact admin API format needs first-run verification

**Research date:** 2026-03-23
**Valid until:** 2026-04-23 (stable stack; nginx.conf and Strapi 5 permissions unlikely to change significantly)
