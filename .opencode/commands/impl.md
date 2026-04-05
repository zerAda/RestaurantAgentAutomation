---
description: Execute implementation from active task context and keep Obsidian state in sync
agent: build
---

Execute implementation from active task context and keep state in sync.

You are the **build** role. You may edit code, run commands, and create files.

Workflow:

1. Read `AGENTS.md` for operating rules
2. Find the active NID in `vault/10-Queue/` or `vault/90-Index/Active NIDs.md`
3. Read the NID note for: objective, subtasks, affected paths, constraints
4. Read linked spec and ADR if they exist in `vault/20-Specs/` and `vault/30-Architecture/`

5. Summarize the implementation plan in 5 bullets max. Show it before proceeding.

6. Implement the changes:
   - Follow the 10-loop quality gate from AGENTS.md
   - Keep commits atomic and well-messaged
   - Use idempotent patterns for migrations
   - Never modify `.env` files
   - Run `git diff --stat` after changes

7. Run the smallest relevant validation:
   - If JS/TS: `npm run lint` or `npm test`
   - If Docker: `docker compose config --quiet`
   - If SQL: check syntax
   - If scripts: `bash -n <script>`

8. Update the NID note in `vault/`:
   - Status: `in_progress` or `done`
   - Files touched
   - Implementation summary
   - Remaining work
   - `updated_at`

9. Return:
   - Files changed (git diff stat)
   - Tests/validation run
   - Open risks
   - Next best command (`/project:test-full`, `/project:session-close`, etc.)
