# RESTO BOT — Skills Index

## Core Skills (13)

| # | Skill | Purpose | Strapi Impact |
|---|-------|---------|---------------|
| 01 | repo_intelligence | Build repo mental model, file paths, trust boundaries | Maps Strapi as critical dependency |
| 02 | architecture_and_security | Validate system invariants, STRIDE threat model | Strapi in threat model scope |
| 03 | ingress_hardening | Traefik TLS, Nginx gateway, /v1 API contract | cms-chain middleware (IP allowlist) |
| 04 | n8n_queue_sre | Queue mode reliability, DLQ, outbox, worker scaling | n8n workflows call Strapi API for config |
| 05 | db_safety_protocol | Backups, restore drills, idempotent migrations | Two DBs: `n8n` + `strapi` |
| 06 | secrets_data_protection | Secret hygiene, rotation, PII, data retention | Strapi JWT/API token secrets |
| 07 | ci_cd_pipeline | 13-workflow GitHub Actions CI/CD system | CMS Docker image build + push |
| 08 | observability | Health endpoints, structured logging, alerts | CMS health: `/_health` on :1337 |
| 09 | release_and_rollback | Safe releases with preflight, deploy, rollback | CMS must be healthy post-deploy |
| 10 | testing_qa | Test strategy, integrity gate, k6 load tests | Strapi API integration tests |
| 11 | workflow_governance | Govern 54 n8n workflow JSONs, Strapi nodes | Strapi REST API integration |
| 12 | supply_chain_security | Docker signing (Cosign), SBOM, SLSA provenance | CMS image signed + attested |
| 13 | vps_operations | VPS deploy, directory layout, env sync, backups | cms_uploads volume, strapi_db_password |

## Strapi CMS — Central Configuration Hub

Strapi is the **single source of truth** for the entire RESTO BOT platform:

- **Bot config**: Menu items, pricing, hours -> consumed by n8n workflows
- **Agent/LLM config**: Prompts, model params -> consumed by n8n + Ollama
- **Dashboard config**: Operational data -> consumed by admin-dashboard
- **Kiosk config**: Menus, orders -> consumed by kiosk-app
- **Feature flags**: Operational parameters stored as Strapi content

**All services depend on Strapi. If Strapi is down, the platform degrades.**

## Usage examples

- "Use 01_repo_intelligence to map the codebase, then 02_architecture_and_security for threat model."
- "Apply 03_ingress_hardening to lock down the cms-chain middleware."
- "Apply 05_db_safety_protocol before running Strapi schema migrations."
- "Use 11_workflow_governance when adding Strapi nodes to n8n workflows."
- "Apply 09_release_and_rollback to produce a release checklist with CMS health verification."
