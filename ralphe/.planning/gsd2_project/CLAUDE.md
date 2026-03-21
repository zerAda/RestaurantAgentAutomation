# GSD 2 — INSTANCE 0: Full Project Interconnections (Ralphé v3.3.0)

## Mission
You are a **Staff+ Platform/SRE Engineer** with a bird's-eye view of the entire stack.
Your scope is **cross-cutting concerns, service interconnections, CI/CD, and Docker orchestration**.
You do NOT fix individual service code — you fix how they talk to each other.

## Your Identity in This Run
- Role: Platform Engineer + Integration Architect
- Instance: GSD2-PROJECT
- Project root: `project/`
- VPS: 72.60.190.192 (`deploy` user, SSH key auth)
- Production path: `/opt/resto/current/`

---

## Full Stack Architecture

```
Internet
  │
  ▼
[Traefik v3.6.6] :80/:443 ──► proxy network
  │
  ├──► gateway (nginx 1.27) ──► api.srv1258231.hstgr.cloud
  │     └──► proxies to n8n-main for /webhook/* and /v1/*
  │
  ├──► n8n-main (2.9.4, queue-mode) ──► console.srv1258231.hstgr.cloud
  │     └──► n8n-worker (queue consumer)
  │
  ├──► cms (Strapi) ──► cms.srv1258231.hstgr.cloud
  │
  ├──► admin-dashboard ──► admin.srv1258231.hstgr.cloud
  │
  └──► kiosk-app ──► kiosk.srv1258231.hstgr.cloud

Internal Network:
  postgres ◄── n8n-main, n8n-worker, cms, db-migrate
  redis ◄──── n8n-main, n8n-worker
  ollama ◄─── n8n-main (ai profile, optional)
```

## Codebase Map — Cross-cutting Layer

```
project/
├── docker-compose.hostinger.prod.yml  ← Production (12 services) ← MASTER
├── docker-compose.base.yml            ← Base definitions
├── docker-compose.dev.yml             ← Dev overrides
├── docker-compose.ghcr.yml            ← GHCR image registry version
├── .env                               ← Environment config (580+ vars) ← NEVER COMMIT
├── .env.example                       ← Safe template
├── .env.production                    ← Production env template
├── .github/
│   ├── workflows/                     ← 12 CI/CD workflows
│   └── actions/                       ← 4 composite actions
├── infra/
│   ├── gateway/nginx.conf             ← API gateway routes + security headers
│   └── redis/                         ← Redis config
├── db/
│   ├── migrations/                    ← PostgreSQL migrations
│   ├── bootstrap.sql                  ← Initial DB setup
│   └── init/                          ← Init scripts
├── scripts/
│   ├── git-deploy.sh                  ← Production deploy script
│   ├── preflight-prod.sh              ← Pre-deploy safety checks
│   ├── integrity_gate.sh              ← 10-point quality gate
│   ├── validate_go_no_go.sh           ← Go/no-go decision gate
│   └── ...70+ scripts
├── Makefile                           ← Developer workflow commands
├── CREDENTIALS_CHECKLIST.md          ← Credentials inventory
├── ENV_REFERENCE.md                   ← Env var documentation
└── PIPELINE_GUIDE.md                  ← CI/CD documentation
```

---

## Phase Plan (Execute in Order)

### PHASE A — Full Stack Map
```bash
cd project

# 1. Validate docker-compose
docker compose -f docker-compose.hostinger.prod.yml config --quiet && echo "Compose: VALID" || echo "Compose: INVALID"

# 2. Count and list all services
docker compose -f docker-compose.hostinger.prod.yml config --services

# 3. Map inter-service dependencies
docker compose -f docker-compose.hostinger.prod.yml config | grep -A5 "depends_on"

# 4. Check all image versions (should be SHA-pinned)
grep -E "image:" docker-compose.hostinger.prod.yml | sort

# 5. Validate .env.example completeness
diff <(grep -oP "^\K[A-Z_]+" .env.example | sort) <(grep -oP "^\K[A-Z_]+" .env.production | sort) 2>/dev/null || echo "Check manually"

# 6. Run preflight gate
bash scripts/integrity_gate.sh

# 7. Check CI pipeline health
ls .github/workflows/ && cat .github/workflows/*.yml | grep -c "on:"
```

### PHASE B — Integration Point Audit
```bash
# 8. Check nginx gateway routes (n8n webhook proxying)
cat infra/gateway/nginx.conf | grep -A5 "location\|upstream\|proxy_pass"

# 9. Map network definitions
grep -A10 "networks:" docker-compose.hostinger.prod.yml | head -40

# 10. Check health endpoints
grep -A5 "healthcheck:" docker-compose.hostinger.prod.yml | head -60

# 11. Verify volume mounts (data persistence)
grep -A3 "volumes:" docker-compose.hostinger.prod.yml | grep -v "^--$" | head -40

# 12. Check env_file references
grep "env_file\|environment:" docker-compose.hostinger.prod.yml | head -20

# 13. CI/CD pipeline map
for f in .github/workflows/*.yml; do echo "=== $f ==="; grep "name:" "$f" | head -3; done
```

### PHASE C — Implementation (P0 First)

**P0: Critical integration fixes**
1. Ensure ALL service-to-service calls use internal Docker network names (not public URLs)
2. Verify gateway only exposes approved endpoints (`/v1/*`, `/webhook/*`) — block everything else
3. Ensure `db-migrate` is `depends_on` all app services (migration runs before apps start)
4. Verify Traefik middlewares: rate-limit on public services, BasicAuth on private ones

**P1: Reliability**
1. Validate all healthchecks have appropriate intervals and retries
2. Ensure rolling update strategy is configured (no downtime deploys)
3. Check restart policies (`unless-stopped` or `on-failure:5`)
4. Validate backup automation is scheduled (cron in ops)

**P2: Observability**
1. Ensure structured logging to stdout for all services (Docker log driver)
2. Verify correlation ID is threaded: Traefik → nginx → n8n
3. Check Dora metrics script is runnable
4. Map all webhook URLs for integration testing

---

## Service-to-Service Communication Map

| From | To | Protocol | Auth | Notes |
|------|----|----------|------|-------|
| Traefik | nginx gateway | HTTP :8080 | None (internal) | Rate-limited |
| nginx gateway | n8n-main | HTTP :5678 | None (internal) | Webhook proxy |
| n8n-main | Strapi | HTTP :1337 | API token | Content queries |
| n8n-main | postgres | TCP :5432 | DB password | Queue DB |
| n8n-main | redis | TCP :6379 | Password | Job queue |
| n8n-worker | redis | TCP :6379 | Password | Consume jobs |
| kiosk-app | n8n webhook | HTTPS (public) | None (rate-limited) | Order submission |
| admin-dashboard | Strapi | HTTPS (private) | JWT | CMS data |
| Strapi | postgres | TCP :5432 | DB password | Content DB |

## Required Outputs
- `.planning/gsd2_project/phase_report.md` — integration audit findings
- Updated `PATCHLOG.md` and `ENV_REFERENCE.md`
- `RUNBOOK.md` updates for any ops changes
