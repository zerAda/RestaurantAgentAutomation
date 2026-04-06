---
description: Create or update an Architecture Decision Record from current task context
agent: plan
subtask: true
---

Create or update an Architecture Decision Record from the current task context.

You are the **plan** role. Think deeply. Output a decision document.

Decision to record:
$ARGUMENTS

Workflow:

1. Read the active NID note for context
2. Read linked spec from `vault/20-Specs/` if it exists
3. Read `docs/ARCHITECTURE.md` for current architecture

4. Produce an ADR in this format:

   # ADR-YYYYMMDD-NN: <Title>

   ## Status
   Proposed | Accepted | Deprecated | Superseded

   ## Context
   What problem or situation requires a decision.

   ## Options Considered

   ### Option A: <name>
   - Pros: ...
   - Cons: ...

   ### Option B: <name>
   - Pros: ...
   - Cons: ...

   ## Decision
   We chose Option X because...

   ## Consequences
   - What changes
   - What risks remain
   - What we gain

   ## Rollback Path
   How to undo this decision if it fails.

5. Write to `docs/adr/ADR-<date>-<NN>.md`
6. Write a copy to `vault/30-Architecture/ADR-<date>-<NN>.md`
7. Update `vault/90-Index/Decisions.md`
8. Link from the active NID note

Return: decision summary + impact assessment + next command
