---
description: Audit workflow topology, triggers, coupling and failure modes
agent: workflow-architect
subtask: true
---

Audit n8n workflow topology, triggers, coupling and failure modes.

You are the **workflow-architect** role. Analyze deeply, don't modify workflows.

Scope:
$ARGUMENTS

Workflow:

1. Count workflows: `ls workflows/*.json 2>/dev/null | wc -l`
2. List all workflow names: `ls workflows/*.json 2>/dev/null | sed 's/.*\///' | sed 's/\.json//' | sort`
3. For the scope area, read the relevant workflow JSON files
4. Read `docs/MAP.md` for workflow topology context

5. Analyze:
   - **Triggers**: webhook, schedule, manual, sub-workflow call
   - **Inputs/Outputs**: what data flows in and out
   - **Coupling points**: which workflows call which
   - **External dependencies**: APIs, databases, Redis, CMS
   - **Retry/failure behavior**: error handling, DLQ, timeouts
   - **Credential usage**: which credentials are referenced

6. Produce:

   ## Workflow Topology
   ```
   trigger → workflow → [outputs/side-effects]
   ```

   ## Dependency Map
   | Workflow | Depends On | Called By |
   |----------|-----------|----------|

   ## Fragile Edges
   Connections likely to break under load or config change.

   ## Missing Observability
   Workflows without error handling or audit hooks.

   ## Refactor Opportunities
   Duplicated logic, over-coupled patterns, dead workflows.

7. Write to `vault/30-Architecture/Workflow Topology.md`
8. Update `vault/90-Index/By Service.md`
9. Return: top risks + recommended actions
