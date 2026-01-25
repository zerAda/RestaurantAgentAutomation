# AGENT 10 — Patch Orchestrator (Master Plan)

## Mission
Coordinate all P0 security and UX patches for production readiness.

## Patch Summary

| ID | Agent | Priority | Status | Files |
|----|-------|----------|--------|-------|
| P0-SEC-01 | Agent 01 | CRITICAL | Ready | nginx.conf.patched |
| P0-SEC-02 | Agent 02 | CRITICAL | Ready | migration SQL |
| P0-SEC-03 | Agent 03 | HIGH | Ready | .env + workflow |
| P0-SUP-01 | Agent 04 | HIGH | Ready | migration SQL |
| P0-L10N-01 | Agent 05 | HIGH | Ready | .env changes |
| P0-OPS-01 | Agent 06 | HIGH | Ready | .env + W8_OPS |
| P0-PERF-01 | Agent 07 | MEDIUM | Ready | migration SQL |
| P0-QA-01 | Agent 08 | HIGH | Ready | smoke tests |

## Deployment Order

### Phase 1: Database Migrations (Non-Breaking)
```bash
# Run in order:
psql -f db/migrations/2026-01-23_p0_sec02_disable_legacy_token.sql
psql -f db/migrations/2026-01-23_p0_sup01_admin_wa_audit.sql
psql -f db/migrations/2026-01-23_p0_perf_indexes.sql
```

### Phase 2: Configuration Updates
```bash
# Update .env from .env.example.patched
# Key changes:
# - LEGACY_SHARED_TOKEN_ENABLED=false
# - WEBHOOK_SHARED_TOKEN= (empty)
# - L10N_ENABLED=true
# - ADMIN_WA_AUDIT_ENABLED=true
# - SIGNATURE_VALIDATION_MODE=warn
```

### Phase 3: Gateway Patch
```bash
# Replace nginx.conf
cp infra/gateway/nginx.conf.patched infra/gateway/nginx.conf

# Reload nginx
docker exec gateway nginx -s reload
```

### Phase 4: Workflow Updates
```bash
# Import updated workflows (if needed)
# Note: Most changes are config-driven via env vars
```

### Phase 5: Validation
```bash
# Run security smoke tests
chmod +x scripts/smoke_security.sh
./scripts/smoke_security.sh

# Run full test harness
./scripts/test_harness.sh

# Run integrity gate
./scripts/integrity_gate.sh
```

## Rollback Plan

### Quick Rollback (Config Only)
```bash
# Revert .env changes:
LEGACY_SHARED_TOKEN_ENABLED=true
WEBHOOK_SHARED_TOKEN=<previous_token>
SIGNATURE_VALIDATION_MODE=off
```

### Full Rollback (DB)
```sql
-- Only if needed - migrations are additive
-- See individual migration files for rollback SQL
```

### Gateway Rollback
```bash
# Restore original nginx.conf
git checkout infra/gateway/nginx.conf
docker exec gateway nginx -s reload
```

## Verification Checklist

### Security
- [ ] Query tokens blocked (curl test with ?token=)
- [ ] Legacy token rejected (curl test)
- [ ] Signature validation logging (check security_events)
- [ ] Rate limiting active (burst test)

### Functionality
- [ ] Arabic input → Arabic response
- [ ] French input → French response
- [ ] Support ticket creation on HELP
- [ ] Admin WA commands work
- [ ] Audit log populated

### Operations
- [ ] Alerts configured
- [ ] Indexes created
- [ ] Retention jobs work
- [ ] Smoke tests pass

## Files Created by Agents

```
project/
├── agents/
│   ├── AGENT_01_SECURITY_GATEWAY.md
│   ├── AGENT_02_DISABLE_LEGACY_TOKEN.md
│   ├── AGENT_03_SIGNATURE_VALIDATION.md
│   ├── AGENT_04_ADMIN_WA_AUDIT.md
│   ├── AGENT_05_L10N_ENABLE.md
│   ├── AGENT_06_SLO_ALERTING.md
│   ├── AGENT_07_PERFORMANCE_INDEXES.md
│   ├── AGENT_08_SMOKE_TESTS_SECURITY.md
│   └── AGENT_10_ORCHESTRATOR.md
├── config/
│   └── .env.example.patched
├── db/migrations/
│   ├── 2026-01-23_p0_sec02_disable_legacy_token.sql
│   ├── 2026-01-23_p0_sup01_admin_wa_audit.sql
│   └── 2026-01-23_p0_perf_indexes.sql
├── infra/gateway/
│   └── nginx.conf.patched
└── scripts/
    └── smoke_security.sh
```

## Post-Deployment Monitoring

### First 24 Hours
- Monitor `security_events` for AUTH_DENY spikes
- Monitor outbox pending age
- Monitor workflow_errors
- Check admin_wa_audit_log population

### First Week
- Review signature validation logs (if warn mode)
- Analyze rate limit triggers
- Verify L10N behavior with real traffic
- Check retention job execution

## Sign-Off Required

- [ ] Security review completed
- [ ] QA tests passed
- [ ] Ops runbooks updated
- [ ] Stakeholder approval

---

**Version**: P0-PATCH-2026-01-23
**Author**: Agent Orchestrator
**Status**: Ready for Review
