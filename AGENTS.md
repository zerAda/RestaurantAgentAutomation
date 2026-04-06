# Ralphé — Agent Instructions

## Project Overview
Restaurant automation platform: WhatsApp/IG/TikTok ordering bot, admin dashboard, kiosk app.
Deployed on Hostinger VPS (72.60.190.192) via Docker Compose.

## Tech Stack
- **Orchestration**: n8n 2.9.4 (queue mode + worker, 97 workflows)
- **CMS**: Strapi 4 on PostgreSQL (via PgBouncer)
- **Frontend**: React + Vite (admin-dashboard, kiosk-app)
- **Cache/Queue**: Redis 7-alpine (256MB, allkeys-lru)
- **Database**: PostgreSQL 15-alpine
- **Gateway**: Nginx 1.27-alpine
- **AI**: Ollama (llama3.1), Whisper STT
- **CI/CD**: GitHub Actions → self-hosted runner on VPS

## Key Conventions
1. **Structured logging**: All n8n Code nodes must use `console.log(JSON.stringify({level, event, ...}))`.
2. **Credential references**: Use `$env.REDIS_CREDENTIAL_ID`, never hardcode credential IDs.
3. **Health checks**: Every Docker service MUST have a healthcheck defined.
4. **Security**: `security_opt: - no-new-privileges:true` and `cap_drop: - ALL` on every container.
5. **Workflow naming**: `W<number>_<NAME>.json` (e.g., `W4_CORE.json`, `W15_OUTBOX_WORKER.json`).
6. **Scripts**: Bash scripts in `scripts/`, must pass `bash -n` syntax check.
7. **Migrations**: SQL files in `db/migrations/`, tracked via `schema_migrations` table.

## File Structure Reminders
- `docker-compose.hostinger.prod.yml` — Production compose (THE source of truth)
- `docker-compose.base.yml` — Shared service definitions
- `Makefile` — All developer and ops commands
- `scripts/git-deploy.sh` — Git-based CD pipeline on VPS
- `scripts/vps-sync.sh` — rsync-based file sync to VPS
- `workflows/` — n8n workflow JSON files (DO NOT edit manually unless patching)
- `infra/redis/entrypoint.sh` — Redis startup with optional auth
- `vps.env` — VPS-specific environment (DO NOT commit secrets here)

## Security Rules
- NEVER commit `.env` or `secrets/` directory.
- Redis password via `REDIS_PASSWORD` env var (optional but recommended).
- Meta webhook signatures: `META_SIGNATURE_REQUIRED=enforce` in production.
| Commande | Agent | Description |
| :--- | :--- | :--- |
| `/bmad-init` | **Planner (R1)** | Initialise un dossier de feature avec PRD et Architecture. |
| `/gsd-run` | **Coder (Kimi)** | Exécute le code en mode autonome sans interruption. |
| `/qa-audit` | **Auditor (R1)** | Analyse le code produit pour valider la qualité Diamond-Grade. |
| `/vps-health` | **Auditor (R1)** | Diagnostic complet de l'infrastructure VPS. |
| `/ralphe-loop`| **Tous** | Cycle complet : Attribution -> Audit -> Optimisation. |
- All sensitive values use Docker secrets mounted at `/run/secrets/`.

## God Mode Architecture
- **Planner (DeepReasoning)**: `DeepSeek R1`. Primary for architecture and complex analytical planning.
- **Coder (Execution)**: `Kimi K2.5`. Primary for high-performance code generation.
- **Auditor (QA/Validation)**: `DeepSeek R1`. Mandatory pass for security and integrity audits.
- **Autonomy**: Full `allow` on `bash`, `edit`, `write`. The agent operates in a closed-loop (Ralphé Loop) for autonomous development.

## Diamond-Grade Execution Standards (Triple-Check)
1. **PLAN (R1)**: Every feature begins with a Reasoning-dense PRD and ARCH.
2. **EXEC (Kimi)**: Code is generated autonomously with Zéro Placeholder.
3. **AUDIT (R1)**: Mandatory QA pass to verify security, performance, and n8n dependencies.
4. **Structured logging**: All n8n Code nodes must use `console.log(JSON.stringify({level, event, ...}))`.

## Deployment & Sync
```bash
# From local: sync + rebuild service
bash scripts/vps-sync.sh --sync cms

# On VPS: full git-based deploy
bash /opt/resto/repo/scripts/git-deploy.sh

# Quick restart (no rebuild)
bash scripts/vps-sync.sh --sync --restart cms

# Ralphé Loop (Autonomous)
/ralphe-loop
```

## BMAD-METHOD Integration

BMAD commands are available as native OpenCode skills in `.opencode/skills/`.
Load the matching skill name (for example `bmad-analyst` or `bmad-create-prd`)
when the user asks for a BMAD workflow or agent. Use the OpenCode question tool (`question`)
when a BMAD workflow needs interactive answers. See `_bmad/COMMANDS.md` for a full reference.

### Phases

| Phase | Focus | Key Agents |
|-------|-------|-----------|
| 1. Analysis | Understand the problem | Analyst agent |
| 2. Planning | Define the solution | Product Manager agent |
| 3. Solutioning | Design the architecture | Architect agent |
| 4. Implementation | Build it | Developer agent, then Ralph autonomous loop |

### Workflow

1. Work through Phases 1-3 using BMAD agents and workflows
2. For PRD creation, use `_bmad/lite/create-prd.md` for single-turn generation
3. Use the bmalph-implement transition to prepare Ralph format, then start Ralph
