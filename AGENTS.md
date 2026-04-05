# AGENTS

## Core Operating Rules

- Default workflow:
  1. `/project:start`
  2. `/project:gsd-triage` to structure any raw request
  3. `/project:mapcodebase` if repo context is incomplete
  4. `/project:bmad-spec` for new scope
  5. `/project:arch-adr` for architectural decisions
  6. `/project:impl`
  7. `/project:test-full`
  8. `/project:session-close`

- Every meaningful task gets a NID:
  - Format: `YYYYMMDD-HHMM-short-slug`
  - Example: `20260404-1645-workflow-audit`

- Every completed task must update:
  1. Code or docs
  2. Obsidian task state (`vault/`)
  3. Decisions if architecture changed
  4. Next-step note

## Source of Truth Split

| Layer | Source | What |
|-------|--------|------|
| **Repo** | Git | Code, infra, schema, configs, scripts, migrations, workflows |
| **Obsidian** | `vault/` | Task state, decisions, progress, working context, handoff state |
| **Planning** | `.planning/` | GSD roadmap, requirements, phase plans (formal project management) |

## Agent Roles

| Agent | Model | Purpose |
|-------|-------|---------|
| **coder** | DeepSeek V3 | Implementation, refactoring, tests, repo operations, doc updates |
| **task** | DeepSeek R1 | Sub-agent: architecture, audit, reasoning, deep analysis |
| **summarizer** | DeepSeek V3 | Auto-compact conversation context |
| **title** | DeepSeek V3 | Generate session titles |

### Conceptual Roles (invoked via commands, not separate agents)

| Role | Triggered by | Model |
|------|-------------|-------|
| **plan** | `/project:gsd-triage`, `/project:bmad-spec`, `/project:arch-adr` | R1 (via task agent) |
| **repo-cartographer** | `/project:mapcodebase` | R1 (via task agent) |
| **workflow-architect** | `/project:workflow-audit` | R1 (via task agent) |
| **platform-sre** | `/project:docker-doctor`, `/project:release-cut` | R1 (via task agent) |
| **vault-curator** | `/project:session-close`, all state updates | V3 (via coder agent) |
| **security-auditor** | `/project:secrets-scan` | R1 (via task agent) |

## Quality Gate (10-loop)

Before finalizing any plan or patch:
1. **Correctness**: works end-to-end?
2. **Contract safety**: keeps `/v1` stable?
3. **Security**: reduces attack surface? New leak paths?
4. **Reliability**: survives retries, timeouts, partial failures?
5. **Ops**: deployable/rollable back quickly?
6. **Observability**: detectable and debuggable?
7. **Data safety**: backups/restore/migrations safe?
8. **Performance**: risk of queue backlog, DB lock, memory blowup?
9. **DX**: new engineer can run it locally?
10. **Audit readiness**: can we explain & prove controls?

## Definition of Done

A task is done only if:
- Change is implemented or explicitly scoped out
- Tests ran or a test gap is documented
- Docs updated when behavior changed
- Obsidian state updated (`vault/`)
- Next step is captured
- No unresolved secret/security leak introduced

## Obsidian Note Convention

Every work note in `vault/` must include frontmatter:

```yaml
---
nid: 20260404-1645-workflow-audit
status: queued | in_progress | blocked | done | cancelled
area:
  - repo
  - workflow
repo_paths: []
decisions: []
related_commands: []
services: []
updated_at: 2026-04-04T16:45:00+02:00
owner: opencode
---
```

## Retrieval Convention

Always search Obsidian notes by:
1. `nid` (unique task ID)
2. `repo_paths` (affected files/dirs)
3. `area` (functional domain)
4. `decisions` (ADR IDs)
5. `services` (docker service names)

## Naming Conventions

- **NIDs**: `YYYYMMDD-HHMM-short-slug`
- **ADRs**: `ADR-YYYYMMDD-NN` (e.g., `ADR-20260404-01`)
- **Commands**: `/project:<name>` (project-level OpenCode commands)
- **Vault paths**: `vault/<NN>-<Category>/<NID or topic>.md`

## Key Security Rules

1. Never commit secrets — check with `/project:secrets-scan` before release
2. Never modify `.env` files through automation
3. Never `docker compose down -v` without explicit confirmation
4. Never force-push to `main` or `release/*`
5. Always verify branch before destructive operations
