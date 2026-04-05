---
description: Generate a real repo map and build the Obsidian retrieval skeleton
agent: repo-cartographer
subtask: true
---

Generate a real repo map and build the Obsidian retrieval skeleton.

You are the **repo-cartographer** role. Analyze deeply, never edit application code.

Workflow:

1. Run: `git ls-files | head -300`
2. Run: `find . -name "package.json" -not -path "*/node_modules/*" -exec echo {} \;`
3. Run: `find . -name "Dockerfile" -o -name "docker-compose*.yml" | sort`
4. Run: `ls workflows/*.json 2>/dev/null | wc -l`
5. Run: `ls db/migrations/*.sql 2>/dev/null`
6. Run: `ls scripts/*.sh 2>/dev/null`
7. Run: `ls .github/workflows/*.yml 2>/dev/null`

Cluster the repo into functional surfaces:

| Surface | Path | Key Files |
|---------|------|-----------|
| Apps | `admin-dashboard/`, `kiosk-app/` | package.json, Dockerfile, src/ |
| CMS | `inventory-cms/` | package.json, Dockerfile, src/api/ |
| Workflows | `workflows/` | W*.json |
| Infra | `infra/`, `docker-compose*.yml` | nginx.conf, Traefik config |
| Database | `db/` | bootstrap.sql, migrations/ |
| Scripts | `scripts/` | smoke tests, deploy tools |
| CI/CD | `.github/workflows/` | ci.yml, cd-deploy.yml |
| Docs | `docs/`, `.planning/` | ARCHITECTURE.md, ROADMAP.md |
| Agent Config | `.opencode/`, `AGENTS.md` | commands, skills |

Then identify:
- **Entrypoints**: compose files, Dockerfiles, package manifests, CI triggers
- **Trust boundaries**: public vs private, network segmentation
- **High-risk areas**: zero test coverage, manual processes, known debt
- **Missing docs**: areas with code but no documentation
- **Ownership clusters**: who/what owns each surface

Write outputs:
1. `vault/90-Index/Repo Map.md` — full structured map
2. `vault/90-Index/By Service.md` — index by Docker service name
3. `vault/90-Index/Entrypoints.md` — all entry points with paths

Return: compact summary + top 5 concerns + recommended next command
