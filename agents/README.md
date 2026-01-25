# P0 Patch Agents — Documentation

## Overview

This directory contains patch agents created to address the security and UX issues identified in the Ralphe audit report (2026-01-23). Each agent focuses on a specific patch area and includes implementation details, rollback instructions, and validation tests.

## Agent Summary

| Agent | ID | Priority | Focus Area |
|-------|-----|----------|------------|
| [AGENT_01](AGENT_01_SECURITY_GATEWAY.md) | P0-SEC-01 | CRITICAL | Gateway query token blocking |
| [AGENT_02](AGENT_02_DISABLE_LEGACY_TOKEN.md) | P0-SEC-02 | CRITICAL | Disable legacy shared token |
| [AGENT_03](AGENT_03_SIGNATURE_VALIDATION.md) | P0-SEC-03 | HIGH | Provider signature validation |
| [AGENT_04](AGENT_04_ADMIN_WA_AUDIT.md) | P0-SUP-01 | HIGH | Admin WhatsApp audit log |
| [AGENT_05](AGENT_05_L10N_ENABLE.md) | P0-L10N-01 | HIGH | Enable L10N by default |
| [AGENT_06](AGENT_06_SLO_ALERTING.md) | P0-OPS-01 | HIGH | SLO alerting & monitoring |
| [AGENT_07](AGENT_07_PERFORMANCE_INDEXES.md) | P0-PERF-01 | MEDIUM | Database performance indexes |
| [AGENT_08](AGENT_08_SMOKE_TESTS_SECURITY.md) | P0-QA-01 | HIGH | Security smoke tests |
| [AGENT_10](AGENT_10_ORCHESTRATOR.md) | - | - | Patch orchestration (master plan) |
| [AGENT_11](AGENT_11_GO_NO_GO_VALIDATOR.md) | - | - | Go/No-Go checklist validator |

## Files Created

### Configuration Patches
- `config/.env.example.patched` - Updated environment configuration

### Infrastructure Patches
- `infra/gateway/nginx.conf.patched` - Gateway with security rules

### Database Migrations
- `db/migrations/2026-01-23_p0_sec02_disable_legacy_token.sql`
- `db/migrations/2026-01-23_p0_sup01_admin_wa_audit.sql`
- `db/migrations/2026-01-23_p0_perf_indexes.sql`

### Scripts
- `scripts/apply_p0_patches.sh` - Automated patch application
- `scripts/smoke_security.sh` - Security smoke tests

## Quick Start

### 1. Review Patches
```bash
# Read the orchestrator plan
cat agents/AGENT_10_ORCHESTRATOR.md
```

### 2. Apply Patches
```bash
# Run the patch application script
chmod +x scripts/apply_p0_patches.sh
./scripts/apply_p0_patches.sh
```

### 3. Apply Database Migrations
```bash
export PGHOST=localhost PGPORT=5432 PGDATABASE=resto PGUSER=postgres

psql -f db/migrations/2026-01-23_p0_sec02_disable_legacy_token.sql
psql -f db/migrations/2026-01-23_p0_sup01_admin_wa_audit.sql
psql -f db/migrations/2026-01-23_p0_perf_indexes.sql
```

### 4. Update Production .env
Copy settings from `config/.env.example.patched` to your production `.env`:
```bash
# Critical settings:
LEGACY_SHARED_TOKEN_ENABLED=false
WEBHOOK_SHARED_TOKEN=
L10N_ENABLED=true
ADMIN_WA_AUDIT_ENABLED=true
SIGNATURE_VALIDATION_MODE=warn
```

### 5. Validate
```bash
# Run security tests
./scripts/smoke_security.sh

# Run full test harness
./scripts/test_harness.sh
```

## Rollback

Each agent includes specific rollback instructions. For a quick rollback:

### Configuration Rollback
```bash
# Restore from backup
cp backups/YYYYMMDD_HHMMSS/.env.example.bak config/.env.example
cp backups/YYYYMMDD_HHMMSS/nginx.conf.bak infra/gateway/nginx.conf
docker exec gateway nginx -s reload
```

### Database Rollback
```sql
-- See individual migration files for specific rollback SQL
-- Migrations are additive; most can remain in place
```

## Audit Trail

These agents were created based on findings from:
- `report/EXEC_SUMMARY.md`
- `report/AUDIT_TECHNICAL.md`
- `report/agents/*.md` (24 specialist agent reports)

The audit identified a health score of **68/100** with **GO-WITH-CONDITIONS** verdict, requiring P0 patches before production deployment.

## Version

- **Patch Version**: P0-2026-01-23
- **Base Version**: resto_n8n_pack_v3.2.1
- **Status**: Ready for Review

## Support

For questions about these patches:
1. Review the individual agent documentation
2. Check the orchestrator plan (AGENT_10)
3. Run the validation tests
4. Consult the original audit report
