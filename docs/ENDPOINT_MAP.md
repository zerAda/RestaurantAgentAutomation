# ENDPOINT_MAP (v3.2.2)

## Security Rules (P0-SEC-01)

**All inbound endpoints enforce:**
- ❌ Query string tokens blocked (`?token=`, `?access_token=`, etc.) → 401 SEC-001
- ✅ Authorization header required: `Authorization: Bearer <token>`
- ⚡ Rate limiting: 10 req/s per IP, 20 req/s per token

## Public endpoints
| Endpoint | Method | Purpose | Proxied to n8n |
|---|---:|---|---|
| `/healthz` | GET | Health check | (handled by gateway) |
| `/v1/inbound/whatsapp` | POST | Inbound WA events | `/webhook/v1/inbound/whatsapp` |
| `/v1/inbound/instagram` | POST | Inbound IG events | `/webhook/v1/inbound/instagram` |
| `/v1/inbound/messenger` | POST | Inbound Messenger events | `/webhook/v1/inbound/messenger` |

## Customer endpoints
| Endpoint | Method | Purpose | Workflow |
|---|---:|---|---|
| `/v1/customer/delivery/quote` | POST | Delivery quote (zone + fee + ETA) | `W10` |

## Admin endpoints
| Endpoint | Method | Purpose | Workflow |
|---|---:|---|---|
| `/v1/admin/ping` | GET | Auth + scopes check | `W9` |
| `/v1/admin/delivery/zones` | GET/POST/DELETE | Delivery zones CRUD | `W11` |
| `/v1/admin/orders` | GET | Orders list + optional timeline | `W12` |

## Aliases (compat)
| Endpoint | Method | Proxied to |
|---|---:|---|
| `/v1/inbound/wa-incoming-v16` | POST | `/webhook/v1/inbound/whatsapp` |
| `/v1/inbound/ig-incoming-v16` | POST | `/webhook/v1/inbound/instagram` |
| `/v1/inbound/msg-incoming-v16` | POST | `/webhook/v1/inbound/messenger` |

## Authentication (P0-SEC-03)

### Recommended: Per-tenant tokens (api_clients)
```bash
curl -X POST https://api.example.com/v1/inbound/whatsapp \
  -H "Authorization: Bearer <api_client_token>" \
  -H "Content-Type: application/json" \
  -d '{"msg_id":"...","from":"...","text":"..."}'
```

### Deprecated: Legacy shared token
- `LEGACY_SHARED_ALLOWED=false` in production
- Attempts logged as `LEGACY_TOKEN_BLOCKED`

## Signature Validation (P0-SEC-02)

For WhatsApp webhooks, validate `X-Hub-Signature-256`:
- `META_SIGNATURE_REQUIRED=false` → warn mode (log only)
- `META_SIGNATURE_REQUIRED=true` → enforce mode (reject invalid)

## Notes
- `/v1/admin/*` et `/v1/customer/*` sont des namespaces privés à protéger (traefik / réseau).
- All security events logged to `security_events` table
