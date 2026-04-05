---
description: Turn a raw request into a structured GSD execution packet with NID and next commands
agent: plan
subtask: true
---

Turn a raw request into a structured GSD execution packet with NID, task breakdown and next commands.

You are the **plan** role. Think deeply before acting. Never edit code directly.

Request to triage:
$ARGUMENTS

Workflow:

1. Generate a new NID using format: `YYYYMMDD-HHMM-short-slug` (use current date/time)

2. Classify the request:
   - bug | feature | audit | infra | db | workflow | security | docs | performance

3. Break the work into:
   - **Objective**: one sentence
   - **Assumptions**: what we're taking for granted
   - **Constraints**: what we cannot change
   - **Subtasks**: ordered list with estimates (S/M/L)
   - **Risks**: what could go wrong
   - **Affected repo paths**: files/directories likely touched
   - **Affected services**: docker services impacted
   - **Recommended commands**: ordered list of `/project:*` commands to execute

4. Check `.planning/REQUIREMENTS.md` — does this map to an existing requirement?

5. Write the triage packet to `vault/10-Queue/<NID>.md` with proper frontmatter:
   ```yaml
   ---
   nid: <NID>
   status: queued
   area: [<classification>]
   repo_paths: [<paths>]
   decisions: []
   related_commands: [<commands>]
   services: [<services>]
   updated_at: <now>
   owner: opencode
   ---
   ```

6. Update `vault/90-Index/Active NIDs.md`

7. Return:
   - NID
   - Priority (P0/P1/P2)
   - Exact next command to run
   - Confidence level (high/medium/low)
