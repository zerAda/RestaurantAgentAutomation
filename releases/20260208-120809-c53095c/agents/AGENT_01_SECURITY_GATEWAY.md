# AGENT 01 — Security Gateway Patch (P0-SEC-01)

## Mission
Block query string tokens at the Nginx gateway level to prevent token leakage in logs.

## Priority
**P0 - CRITICAL** - Must be deployed before production.

## Problem Statement
- `ALLOW_QUERY_TOKEN=true` allows tokens via `?token=xxx` in URL
- Tokens in URLs leak to proxy logs, browser history, referer headers
- Attack vector: compromise token from logs → webhook spoofing

## Solution
Add Nginx rules to reject requests with `token` or `access_token` in query string.

## Files Modified
- `infra/gateway/nginx.conf`
- `infra/gateway/nginx.test.conf`

## Implementation

### nginx.conf changes
```nginx
# Add at the top of server block, after listen directive:

# P0-SEC-01: Block query string tokens (security)
set $block_query_token 0;
if ($arg_token) {
    set $block_query_token 1;
}
if ($arg_access_token) {
    set $block_query_token 1;
}

# Apply to inbound endpoints
location = /v1/inbound/whatsapp {
    if ($block_query_token) {
        return 401 '{"error":"query_token_blocked","code":"SEC-001"}';
    }
    proxy_pass http://n8n_upstream/webhook/v1/inbound/whatsapp;
    include /etc/nginx/proxy_params;
}
```

## Rollback
Remove the `set $block_query_token` and `if ($block_query_token)` blocks.

## Tests
```bash
# Should return 401
curl -X POST "https://api.example.com/v1/inbound/whatsapp?token=xxx" -d '{}'

# Should work (header auth)
curl -X POST "https://api.example.com/v1/inbound/whatsapp" \
  -H "Authorization: Bearer xxx" -d '{}'
```

## Validation Checklist
- [ ] Query token requests return 401
- [ ] Header/Bearer auth still works
- [ ] security_events logs AUTH_DENY for blocked requests
- [ ] No regression on legitimate traffic
