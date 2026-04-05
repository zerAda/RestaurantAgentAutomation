---
description: Generate a BMAD spec packet linked to the active NID
agent: plan
subtask: true
---

Generate a BMAD-style spec packet linked to the active NID.

You are the **plan** role. Think deeply. Never edit application code.

Scope to spec:
$ARGUMENTS

Workflow:

1. Read the active NID note from `vault/10-Queue/` or `vault/00-Inbox/`
2. Read `.planning/REQUIREMENTS.md` for relevant requirements
3. Read `docs/ARCHITECTURE.md` for system context

4. Produce a structured spec:

   ## Problem Statement
   One paragraph: what's broken or missing.

   ## Target Outcome
   What success looks like, measurable.

   ## Scope In
   Bullet list of what's included.

   ## Scope Out
   Bullet list of what's explicitly excluded.

   ## Impacted Surfaces
   Which repo paths, services, APIs are affected.

   ## Operational Risks
   What could go wrong in production.

   ## Database Risks
   Migration safety, data integrity, backup needs.

   ## Rollout Considerations
   Deploy order, feature flags, rollback path.

   ## Validation Plan
   How to verify the change works (smoke tests, manual checks).

   ## Acceptance Criteria
   Numbered list of must-pass conditions.

5. Write the spec to `vault/20-Specs/<NID>-spec.md`
6. Link it from the active NID note
7. Return: spec summary + exact next command (usually `/project:arch-adr` or `/project:impl`)
