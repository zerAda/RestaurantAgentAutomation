---
name: architecture_and_security
description: Protect system invariants and run threat analysis before changes.
when_to_use:
  - Planning refactors or new features
  - Changing routing, auth, or service topology
  - Security review or audit
  - Before exposing any new endpoint
---

# Architecture & Security Guardian

## System invariants (must remain true)

1. `/v1/*` public contract is backward compatible (additive only)
2. n8n is NOT a public API surface; gateway is the entrypoint
3. `console.<domain>` is private (IP allowlist + BasicAuth in Traefik labels)
4. Auth validated BEFORE upstream proxy (gateway level)
5. Query-token auth is OFF by default (`ALLOW_QUERY_TOKEN=false`)
6. Inbound processing is idempotent (dedupe by message/event ID)
7. DB changes are idempotent with backup/restore capability
8. Queue mode in prod with explicit worker concurrency
9. All Strapi nodes enforce `tenant_context` in `restaurant_id.$eq` filter
10. No secrets in git, logs, or workflow JSON

## Review gate (answer explicitly for every change)

1. Which invariant could this change weaken? (cite number)
2. What is the auth flow end-to-end?
3. What is the rollback plan?
4. What is the minimal smoke test proving safety?

## Threat analysis (when security-relevant)

Apply STRIDE to the change scope:

- **S**poofing: Can the auth be bypassed?
- **T**ampering: Can request/response be modified?
- **R**epudiation: Is the action logged?
- **I**nfo disclosure: Does it leak secrets, PII, or internal paths?
- **D**oS: Does it increase attack surface or remove rate limits?
- **E**levation: Can it bypass tenant isolation or admin checks?

## Evidence files for controls

| Control | File |
|---------|------|
| Gateway auth | `infra/gateway/nginx.conf` |
| Rate limits | Traefik labels in `docker-compose.hostinger.prod.yml` |
| Meta signature | `workflows/W0_META_VERIFY_UNIFIED.json` |
| Token scope | `B0 - Token OK?` in W1/W2/W3 |
| Admin gate | `B1a - Admin Access Validator (SECURED)` in W1_IN_WA |
| Tenant isolation | `integrity_gate.sh` (Strapi tenant filter check) |
| Secret scan | `.github/workflows/security-scan.yml` |
| Idempotency | dedupe key in workflow ingestion nodes |

## Deliverables

- Invariant impact assessment (pass/fail per invariant, citing evidence)
- Threat assessment (if security-relevant)
- Safer alternative if any invariant is at risk
- Rollback plan
