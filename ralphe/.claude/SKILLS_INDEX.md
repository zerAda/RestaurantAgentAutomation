# RESTO BOT — Skills Index v2.0

## Skill map (13 active skills)

| # | Skill | Domain | Key files |
|---|-------|--------|-----------|
| 01 | repo_intelligence | Codebase orientation | All infrastructure files |
| 02 | architecture_and_security | Invariant protection + STRIDE | CLAUDE.md, nginx.conf, compose |
| 03 | ingress_hardening | Traefik + Nginx gateway | compose labels, infra/gateway/ |
| 04 | n8n_queue_sre | Queue reliability, DLQ, outbox | W8_*, W15_*, W16_*, W17_* |
| 05 | db_safety_protocol | Backups, migrations, restore | db/, scripts/backup_*, scripts/restore_* |
| 06 | secrets_data_protection | Secrets, PII, rotation, retention | .env, security-scan.yml, integrity_gate.sh |
| 07 | ci_cd_pipeline | 13 GHA workflows, composite actions | .github/workflows/, .github/actions/ |
| 08 | observability | Health, logs, alerts, DORA | W16_HEALTHZ, deep-health-check.sh, notify action |
| 09 | release_and_rollback | Deploy, verify, incident response | cd-deploy.yml, rollback.yml, smoke scripts |
| 10 | testing_qa | Integrity gate, test battery, k6, fixtures | integrity_gate.sh, tests/, scripts/test_* |
| 11 | workflow_governance | n8n workflow structure, tenant isolation | workflows/, integrity_gate.sh, workflow-validate.yml |
| 12 | supply_chain_security | Cosign, SBOM, SLSA, GHCR | build-push-artifacts.yml, cosign keys |
| 13 | vps_operations | SSH deploy, env sync, backups, VPS layout | cd-deploy.yml, /opt/resto/, scripts/ops/ |

## Deprecated skills (merged)

- ~~14_performance_capacity_planning~~ -> 04 + 10
- ~~15_data_privacy_compliance~~ -> 06
- ~~16_change_management_governance~~ -> 07
- ~~17_multi_tenant_futureproofing~~ -> 11

## Usage patterns

- **First session**: `01_repo_intelligence` to build mental model
- **Before any change**: `02_architecture_and_security` for invariant check
- **Editing gateway/routing**: `03_ingress_hardening`
- **Queue issues**: `04_n8n_queue_sre`
- **Schema changes**: `05_db_safety_protocol`
- **Adding secrets/integrations**: `06_secrets_data_protection`
- **CI/CD pipeline work**: `07_ci_cd_pipeline`
- **Debugging production**: `08_observability` + `09_release_and_rollback`
- **Adding tests**: `10_testing_qa`
- **Modifying workflows**: `11_workflow_governance`
- **Docker image pipeline**: `12_supply_chain_security`
- **VPS operations**: `13_vps_operations`
- **Full release**: `05` (backup) -> `10` (tests) -> `09` (release) -> `08` (monitor)
