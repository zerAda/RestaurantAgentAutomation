# Schemas

This folder is the **single source of truth** for inbound webhook payload contracts.

- `schemas/inbound/v1.json` — initial "Inbound Envelope" contract (compat layer maps legacy provider payloads to this).
- `schemas/inbound/v2.json` — normalized structure (sender/message), stricter attachment MIME rules.

## Contract selection (versioning)

The inbound workflows determine the contract version in this order:

1. HTTP header `x-contract-version` (preferred)
2. Body field `contract_version` / `contractVersion`
3. Default: `v1`

Accepted values: `v1`, `v2`, `1`, `2` (normalized to `v1` / `v2`).

Unknown versions are rejected with **HTTP 400** and a `security_events` entry:
`CONTRACT_VALIDATION_FAILED`.

## Multi-tenant context

Inbound payloads may contain `tenant_context` but it is **never trusted**.

Authoritative tenant context is resolved via the API client token in `api_clients` and then sealed:

- `tenant_context` is set from DB (`auth_db`) or legacy fallback (`legacy_shared`)
- `tenant_context_seal` is a SHA-256 hash of the resolved context
- `tenant_context_seal` is verified before CORE execution

## Provider mapping → envelope

| Provider | Existing raw fields (legacy) | Envelope v1 mapping | Envelope v2 mapping |
|---|---|---|---|
| WhatsApp (`wa`) | `from`, `msgId/messageId`, `text`, `audioUrl` | `from`, `msg_id`, `text`, `attachments[0]=audio` | `sender.id`, `msg_id`, `message.text/attachments` |
| Instagram (`ig`) | `sender`, `message.id`, `message.text`, `audio.url` | `from`, `msg_id`, `text`, `attachments[0]=audio` | `sender.id`, `msg_id`, `message.text/attachments` |
| Messenger (`msg`) | `sender`, `mid`, `text`, `attachments[]` | `from`, `msg_id`, `text`, `attachments[]` | `sender.id`, `msg_id`, `message.text/attachments` |

If the inbound payload already matches the envelope (v1/v2), no mapping is applied.

## Backward compatibility & migration rules

- **v1 is the default** and remains supported.
- v2 is additive and should be adopted by upstream senders via `x-contract-version: v2`.
- Removing a field requires a new major version (v3+).
- Adding optional fields is allowed in the same major version.
- No field changes are allowed without updating:
  - schema file
  - workflow validation code
  - docs (`docs/API_CONVENTIONS.md`, `docs/CHANGELOG.md`)
  - tests (`scripts/validate_contracts.py`, `TEST_REPORT.md`)
