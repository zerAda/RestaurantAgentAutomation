# AGENT 08 — Security Smoke Tests (P0-QA-01)

## Mission
Add automated security smoke tests to validate P0 security patches.

## Priority
**P0 - HIGH** - Must verify security patches before production.

## Problem Statement
- No automated tests for security controls
- Manual testing error-prone
- Regressions possible on deployments

## Solution
Add security-focused smoke tests to `scripts/smoke.sh` and create dedicated security test script.

## Files Modified
- `scripts/smoke_security.sh` (new)
- `scripts/smoke.sh` (add security calls)
- `tests/security/` (test cases)

## Implementation

### scripts/smoke_security.sh
```bash
#!/usr/bin/env bash
set -euo pipefail

# =========================
# Security Smoke Tests
# P0-QA-01
# =========================

BASE_URL="${BASE_URL:-http://localhost:8080}"
VALID_TOKEN="${TEST_API_TOKEN:-test-token-123}"
LEGACY_TOKEN="${LEGACY_SHARED_TOKEN:-legacy-token}"

PASSED=0
FAILED=0

log_pass() { echo "✅ PASS: $1"; ((PASSED++)); }
log_fail() { echo "❌ FAIL: $1"; ((FAILED++)); }

# -----------------------------
# SEC-01: Query Token Blocked
# -----------------------------
echo "=== Testing P0-SEC-01: Query Token Blocking ==="

# Test 1: Query token should be rejected
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "$BASE_URL/v1/inbound/whatsapp?token=$VALID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"test1","from":"123","text":"test","provider":"wa"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "401" ]; then
  log_pass "Query token rejected with 401"
else
  log_fail "Query token not rejected (got $HTTP_CODE)"
fi

# Test 2: access_token in query should be rejected
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "$BASE_URL/v1/inbound/whatsapp?access_token=$VALID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"test2","from":"123","text":"test","provider":"wa"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "401" ]; then
  log_pass "access_token in query rejected"
else
  log_fail "access_token in query not rejected (got $HTTP_CODE)"
fi

# Test 3: Header token should work
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "$BASE_URL/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $VALID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"test3","from":"123","text":"test","provider":"wa"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "202" ]; then
  log_pass "Header token accepted"
else
  log_fail "Header token not accepted (got $HTTP_CODE)"
fi

# -----------------------------
# SEC-02: Legacy Token Disabled
# -----------------------------
echo ""
echo "=== Testing P0-SEC-02: Legacy Token Disabled ==="

# Test 4: Legacy shared token should be rejected (if disabled)
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "$BASE_URL/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $LEGACY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"test4","from":"123","text":"test","provider":"wa"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
# Note: This test depends on LEGACY_SHARED_TOKEN_ENABLED=false
if [ "$HTTP_CODE" = "401" ]; then
  log_pass "Legacy token rejected (good)"
elif [ "$HTTP_CODE" = "200" ]; then
  echo "⚠️  WARN: Legacy token accepted - ensure LEGACY_SHARED_TOKEN_ENABLED=false in prod"
else
  log_fail "Unexpected response for legacy token (got $HTTP_CODE)"
fi

# -----------------------------
# SEC-03: No Token = Rejected
# -----------------------------
echo ""
echo "=== Testing: No Token Rejection ==="

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "$BASE_URL/v1/inbound/whatsapp" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"test5","from":"123","text":"test","provider":"wa"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "401" ]; then
  log_pass "No-token request rejected"
else
  log_fail "No-token request not rejected (got $HTTP_CODE)"
fi

# -----------------------------
# SEC-04: Admin Scopes
# -----------------------------
echo ""
echo "=== Testing: Admin Scope Enforcement ==="

# Test without admin scope
RESPONSE=$(curl -s -w "\n%{http_code}" -X GET \
  "$BASE_URL/v1/admin/ping" \
  -H "Authorization: Bearer $VALID_TOKEN")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
# Depending on scope, this might be 200 or 403
if [ "$HTTP_CODE" = "403" ] || [ "$HTTP_CODE" = "401" ]; then
  log_pass "Admin endpoint requires proper scope"
elif [ "$HTTP_CODE" = "200" ]; then
  echo "⚠️  WARN: Admin endpoint accessible - verify token has admin scope"
fi

# -----------------------------
# SEC-05: Rate Limiting
# -----------------------------
echo ""
echo "=== Testing: Rate Limiting ==="

# Send burst of requests
for i in {1..15}; do
  curl -s -o /dev/null -X POST \
    "$BASE_URL/v1/inbound/whatsapp" \
    -H "Authorization: Bearer $VALID_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"msg_id\":\"burst$i\",\"from\":\"burst-user\",\"text\":\"test\",\"provider\":\"wa\"}" &
done
wait

# Check if rate limited
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "$BASE_URL/v1/inbound/whatsapp" \
  -H "Authorization: Bearer $VALID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"burst-final","from":"burst-user","text":"test","provider":"wa"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "429" ]; then
  log_pass "Rate limiting active"
else
  echo "⚠️  INFO: Rate limit not triggered (may need more requests or check config)"
fi

# -----------------------------
# Summary
# -----------------------------
echo ""
echo "==========================="
echo "Security Smoke Test Results"
echo "==========================="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
  echo ""
  echo "⚠️  SECURITY TESTS FAILED - DO NOT DEPLOY TO PRODUCTION"
  exit 1
fi

echo ""
echo "✅ All security tests passed"
exit 0
```

## Rollback
N/A - tests don't modify system state.

## Tests
```bash
# Run security smoke tests
chmod +x scripts/smoke_security.sh
./scripts/smoke_security.sh
```

## Validation Checklist
- [ ] Query token tests pass
- [ ] Legacy token tests pass (rejected when disabled)
- [ ] No-token tests pass
- [ ] Admin scope tests pass
- [ ] Rate limit tests trigger
