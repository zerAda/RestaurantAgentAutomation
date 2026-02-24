# AGENT 11 — Go/No-Go Checklist Validator

## Mission
Automated validation of the 50-point Go/No-Go checklist before production deployment.

## Priority
**P0 - CRITICAL** - Must pass before any production deployment.

## Implementation

### Automated Checks (can be scripted)

#### Security & Auth (10 points)
```bash
# 1. Webhooks reject requests without token
curl -s -o /dev/null -w "%{http_code}" -X POST "$URL/v1/inbound/whatsapp" -d '{}' | grep -q "401"

# 2. Gateway blocks query tokens
curl -s -o /dev/null -w "%{http_code}" "$URL/v1/inbound/whatsapp?token=test" | grep -q "401"

# 3. WEBHOOK_SHARED_TOKEN is empty (check .env)
grep -q "WEBHOOK_SHARED_TOKEN=$" .env || grep -q "WEBHOOK_SHARED_TOKEN=\"\"" .env

# 4. Scopes enforced on admin endpoints
curl -s -o /dev/null -w "%{http_code}" "$URL/v1/admin/ping" -H "Authorization: Bearer no-scope" | grep -qE "401|403"

# 5. ADMIN_ALLOWED_IPS is /32 only
grep "ADMIN_ALLOWED_IPS" .env | grep -q "/32"

# 6. Secrets not in repo
! grep -rq "WA_API_TOKEN=" --include="*.json" --include="*.sql" .

# 7. Rate limit active
# (requires burst test)

# 8. Schema validation active
curl -s "$URL/v1/inbound/whatsapp" -H "Authorization: Bearer $TOKEN" -d '{"invalid":true}' | grep -q "CONTRACT_REJECT\|validation"

# 9. Idempotency works
# (requires duplicate test)

# 10. Admin WA requires owner/admin role
# (requires role test)
```

#### Reliability (10 points)
```bash
# 11. Outbox retry configured
grep -q "OUTBOX_MAX_ATTEMPTS" .env

# 12. SLO monitoring
grep -q "ALERT_OUTBOX_PENDING" .env

# 13. DLQ alerting
grep -q "ALERT_DLQ_COUNT" .env

# 14. Workers deployed
docker ps | grep -q "n8n.*worker"

# 15. Timeout configured
grep -q "OUTBOX_BASE_DELAY" .env

# 16. Provider failure doesn't lose messages
# (requires failure simulation)

# 17. Error trigger writes to DB
psql -c "SELECT COUNT(*) FROM workflow_errors" | grep -q "[0-9]"

# 18. Alert webhook works
curl -s "$ALERT_WEBHOOK_URL" -d '{"test":true}' | grep -q "ok\|200"

# 19. Retention job configured
grep -q "RETENTION_DAYS" .env

# 20. Integrity gate passes
./scripts/integrity_gate.sh
```

#### DB & Data (10 points)
```bash
# 21. Migrations idempotent
psql -f db/migrations/*.sql && psql -f db/migrations/*.sql  # Run twice

# 22. Indexes present
psql -c "SELECT indexname FROM pg_indexes WHERE schemaname='public'" | grep -q "idx_"

# 23. Event type constraints
psql -c "\d security_events" | grep -q "CHECK"

# 24. Backup script works
./scripts/backup_postgres.sh

# 25. Restore drill completed
# (manual verification required)

# 26. RPO/RTO documented
grep -q "RPO\|RTO" docs/*.md

# 27. Table sizes monitored
# (requires monitoring setup)

# 28. FKs exist
psql -c "SELECT conname FROM pg_constraint WHERE contype='f'" | grep -q "fk\|_id"

# 29. No SQL injection
! grep -rq "\$\{.*\}" --include="*.sql" .  # No string interpolation

# 30. Timezone correct
grep -q "TZ=Europe/Paris\|TZ=Africa/Algiers" .env
```

#### WhatsApp Admin & Support (10 points)
```bash
# 31. Admin console enabled
grep -q "ADMIN_WA_CONSOLE_ENABLED=true" .env

# 32. W14 imported
grep -q "ADMIN_WA_CONSOLE_WORKFLOW_ID" .env

# 33. Support enabled
grep -q "SUPPORT_ENABLED=true" .env

# 34. Agent take/reply works
# (requires manual test)

# 35. Audit trail active
grep -q "ADMIN_WA_AUDIT_ENABLED=true" .env

# 36. Escalation message configured
# (requires manual test)

# 37. No UI required
# (design verification)

# 38. Permissions reviewed
# (manual verification)

# 39. Rate limit on admin
# (requires test)

# 40. Logs include ticket_id
psql -c "SELECT * FROM admin_wa_audit_log LIMIT 1" | grep -q "target_id"
```

#### Localization & UX (10 points)
```bash
# 41. L10N enabled
grep -q "L10N_ENABLED=true" .env

# 42. Sticky AR active
grep -q "L10N_STICKY_AR_ENABLED=true" .env

# 43. Fallback FR configured
grep -q "L10N_FALLBACK_LOCALE=fr" .env

# 44. Templates exist FR/AR
ls templates/whatsapp/*.fr.json templates/whatsapp/*.ar.json

# 45. Messages short with emojis
# (content review)

# 46. LANG command works
# (requires test)

# 47. AR content reviewed
# (manual verification)

# 48. Error templates exist
grep -q "ERROR" templates/whatsapp/*.json

# 49. SMS templates exist (if used)
# (optional)

# 50. WhatsApp policies respected
# (compliance review)
```

## Validation Script

See `scripts/validate_go_no_go.sh` for automated execution.

## Manual Checklist Items

Some items require manual verification:
- Restore drill completed with proof
- AR content reviewed by native speaker
- WhatsApp policies compliance reviewed
- Security review signed off
- Stakeholder approval obtained

## Sign-Off Template

```
GO/NO-GO CHECKLIST SIGN-OFF
===========================
Date: _______________
Version: _______________

Automated Checks: ___/40 passed
Manual Checks: ___/10 verified

Security Review: [ ] Approved by: _______________
QA Review: [ ] Approved by: _______________
Ops Review: [ ] Approved by: _______________
Stakeholder: [ ] Approved by: _______________

DECISION: [ ] GO  [ ] NO-GO

Notes:
_____________________________________
_____________________________________
```
