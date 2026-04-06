---
description: Load repo state, active NIDs, recent decisions and current branch context
agent: build
---

Load repo state, active NIDs, recent decisions and current branch context for a new session.

Do the following in order:

1. Read `AGENTS.md` and `opencode.md` to load operating rules
2. Run: `git branch --show-current && echo "---" && git status --short && echo "---" && git log --oneline -5`
3. Read `.planning/STATE.md` for current project position
4. Read `.planning/ROADMAP.md` for phase overview
5. Search `vault/90-Index/Active NIDs.md` for active work items
6. Search `vault/90-Index/Decisions.md` for recent decisions
7. Search `vault/60-Observability/` for the latest session log

Produce a concise session start report:
- **Branch**: current branch + clean/dirty status
- **Project phase**: current phase from STATE.md
- **Active NIDs**: list with status
- **Blocked items**: if any
- **Latest decisions**: last 3
- **Last session**: what happened + where we stopped
- **Recommended next command**: what to do first
- **Risks / missing context**: anything suspicious
