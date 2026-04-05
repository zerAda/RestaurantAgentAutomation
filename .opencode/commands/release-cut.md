---
description: Prepare a clean release packet with risks, checks and notes
agent: platform-sre
subtask: true
---

Prepare a clean release packet with risks, checks and notes.

You are the **platform-sre** role. Assess readiness, don't auto-deploy.

Release scope:
$ARGUMENTS

Workflow:

1. Check current state:
   - Run: `git log --oneline -10`
   - Run: `git diff --stat HEAD~5`
   - Run: `git status --short`

2. Read `.planning/STATE.md` for project position
3. Read `.planning/REQUIREMENTS.md` for completion status
4. Check active NID notes in `vault/90-Index/Active NIDs.md`

5. Identify risks:
   - **Code risks**: untested changes, large diffs
   - **Migration risks**: new SQL migrations, schema changes
   - **Config risks**: new env vars needed, compose changes
   - **Rollback risks**: is rollback safe? Data migrations?
   - **Missing docs**: changes without updated documentation

6. Produce:

   ## Release Summary
   Version, scope, key changes.

   ## Pre-flight Checklist
   - [ ] All tests pass
   - [ ] No uncommitted changes
   - [ ] Migrations are idempotent
   - [ ] ENV_REFERENCE.md updated
   - [ ] No secrets in diff
   - [ ] Compose config validates
   - [ ] Rollback path documented

   ## Risks
   | Risk | Severity | Mitigation |
   |------|----------|------------|

   ## Rollout Checklist
   Step-by-step deploy instructions.

   ## Rollback Checklist
   Step-by-step rollback instructions.

   ## Verdict
   GO / NO-GO / CONDITIONAL-GO (with conditions)

7. Write to `vault/40-Runbooks/Release-<date>.md`
8. Return: verdict + blockers if any
