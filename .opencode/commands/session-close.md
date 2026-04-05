---
description: Close the session cleanly and persist state for the next agent/session
agent: vault-curator
subtask: true
---

Close the current session cleanly and persist state for the next agent/session.

Workflow:

1. Gather session state:
   - Active NID(s) worked on
   - Run: `git diff --stat` for uncommitted changes
   - Run: `git log --oneline -5` for recent commits
   - Decisions made during this session
   - Remaining blockers or open questions

2. For each active NID, update the note in `vault/`:
   - `status`: update to current state (done, in_progress, blocked)
   - `repo_paths`: update with files actually touched
   - `updated_at`: now
   - Add implementation summary if work was done
   - Add remaining work if incomplete

3. Write/update session log:
   - `vault/60-Observability/Session-<YYYYMMDD-HHMM>.md`
   - Include: NIDs worked, files changed, decisions, time spent

4. Update indexes:
   - `vault/90-Index/Active NIDs.md` — refresh status list
   - `vault/90-Index/Decisions.md` — append new decisions

5. Update `.planning/STATE.md` if project-level progress was made

6. Produce handoff summary:

   ## Session Summary
   What was accomplished.

   ## Files Changed
   Git diff stat.

   ## Decisions Made
   List with ADR references.

   ## Open Items
   What's left unfinished.

   ## Next Session Start
   Exact command: `/project:start` then `/project:<recommended>`

   ## Confidence
   How confident are we the state is clean (high/medium/low)
