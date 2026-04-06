---
type: index
updated_at: 2026-04-04T18:00:00+02:00
---

# Decisions Index

## Active ADRs

_None yet — use `/project:arch-adr` to create the first ADR._

## Historical Decisions (from .planning/STATE.md)

| Date | Decision | Context |
|------|----------|---------|
| 2026-03-18 | Fix-first milestone: no new features | Platform is live; stabilize before extending |
| 2026-03-18 | CMS routes via TS source | Never runtime injection via docker cp |
| 2026-03-18 | Node.js 18 → 20 across all Dockerfiles | EOL security fix |
| 2026-03-18 | Phase 4 depends on Phase 1 (not 3) | Routing tests need stable CMS but not metrics |
| 2026-03-23 | OBS-01 blocked on n8n upgrade | VPS n8n 1.80.0 doesn't support N8N_LOG_FORMAT=json |

---

> Updated by `/project:arch-adr` and `/project:session-close`.
