# Obsidient Schema Reference

> **Version**: 1.0.0
> **Purpose**: Data structure reference for Obsidient knowledge base

---

## File Types

### 1. Task Files

**Location**: `.obsidient/tasks/{active,completed,archived}/TASK-{seq}-{slug}.md`

**Schema**:
```yaml
---
task_id: string          # Format: TASK-{3-digit sequence}
title: string           # Human-readable description
status: enum            # active | completed | archived
phase: enum             # analysis | planning | solutioning | implementation
method: enum            # bmad | gsd | ralphe
created: ISO8601        # Creation timestamp
updated: ISO8601        # Last update timestamp
components: string[]    # Affected components
---

## Objective
Plain text description of the task goal.

## Method History
Auto-generated list of commands executed:
- **{method}-{command}** → {result} [{timestamp}]

## Progress
Checklist of work items:
- [ ] Item 1
- [x] Item 2 (completed)

## Context
Shared context updated by all methods.
Key-value pairs, notes, blockers.

## Decisions Referenced
Links to decision files:
- [DEC-XXX] Decision title

## Notes
Manual notes section.

## Resources
Links to external resources.
```

**Example**:
```markdown
---
task_id: TASK-001
title: "WhatsApp Ordering Integration"
status: active
phase: implementation
method: ralphe
created: 2026-04-04T10:00:00Z
updated: 2026-04-04T14:30:00Z
components:
  - n8n/workflows
  - admin-dashboard
  - strapi-backend
---

## Objective
Implement WhatsApp ordering bot for restaurant automation.

## Method History
- **bmad-create-prd** → PRD generated [2026-04-04T10:30:00Z]
- **bmad-create-architecture** → ARCH approved [2026-04-04T11:00:00Z]
- **ralphe-run** → Implementation started [2026-04-04T14:30:00Z]

## Progress
- [x] PRD Created
- [x] Architecture Defined
- [x] Stories Generated
- [ ] Implementation (75%)
- [ ] Audit

## Context
Current story: Story-05 - Webhook handler
Blocks: None
Last loop: #15
Files modified: 12

## Decisions Referenced
- [DEC-001] Use WhatsApp Business API
- [DEC-002] Webhook validation pattern

## Notes
Webhook endpoint tested successfully.

## Resources
- PRD: .planning/PRD-whatsapp.md
- Architecture: .planning/ARCH-whatsapp.md
```

---

### 2. Decision Files

**Location**: `.obsidient/decisions/DEC-{seq}-{slug}.md`

**Schema**:
```yaml
---
decision_id: string      # Format: DEC-{3-digit sequence}
title: string           # Decision title
date: ISO8601          # Decision date
status: enum           # proposed | accepted | deprecated
task: string           # Related task ID (optional)
---

## Context
What led to this decision.

## Problem Statement
The problem being solved.

## Options Considered

### Option 1: {Name}
**Pros:**
- 

**Cons:**
- 

### Option 2: {Name}
**Pros:**
- 

**Cons:**
- 

## Decision
Chosen option and rationale.

## Consequences
Impact on project (positive, negative, neutral).

## Related Decisions
Links to related decisions.

## References
External links and documentation.
```

**Example**:
```markdown
---
decision_id: DEC-001
title: "Use WhatsApp Business API over Twilio"
date: 2026-04-04T11:00:00Z
status: accepted
task: TASK-001
---

## Context
Task TASK-001 requires WhatsApp integration for order processing.

## Problem Statement
Choose between WhatsApp Business API and Twilio for WhatsApp messaging.

## Options Considered

### Option 1: WhatsApp Business API (Direct)
**Pros:**
- Lower cost per message
- Direct Meta relationship
- Rich media support

**Cons:**
- Complex setup
- Requires business verification

### Option 2: Twilio
**Pros:**
- Easier setup
- Unified API for multiple channels
- Better documentation

**Cons:**
- Higher cost
- Middleman dependency

## Decision
Use WhatsApp Business API directly.

Rationale: Lower ongoing costs and direct control outweigh setup complexity.

## Consequences

### Positive
- 40% lower messaging costs
- Direct access to new features

### Negative
- 2-week setup time for business verification

### Neutral
- Need to maintain own webhook infrastructure

## Related Decisions
None.

## References
- WhatsApp Business API docs: https://business.whatsapp.com/products/business-platform
- Twilio WhatsApp: https://www.twilio.com/whatsapp
```

---

### 3. Session Context

**Location**: `.obsidient/context/current-session.md`

**Schema**:
```yaml
---
session_id: string       # Unique session identifier
updated: ISO8601        # Last update timestamp
---

## Active Tasks
List of active tasks with phase and method.

## Current Focus
Task, story, component, last action.

## Recent Context
Summary of recent activity.

## Cross-Task Context
Shared components, dependencies.

## Method Handoff [timestamp]
Record of method transitions.
```

---

### 4. Project State

**Location**: `.obsidient/context/project-state.md`

**Schema**:
```yaml
---
updated: ISO8601
version: string
---

## Overall Status
Summary of project health.

## Component Status
Table of components and their status.

## Active Milestones
Current milestones and progress.

## Blockers
Current blockers and their impact.

## Metrics
Key project metrics.
```

---

### 5. Context Snapshots

**Location**: `.obsidient/context/snapshots/snap-{timestamp}.md`

**Schema**:
```yaml
---
snapshot_id: timestamp
task: string
timestamp: ISO8601
trigger: string
---

## Session State
Full session context at snapshot time.

## Task State
Task file content at snapshot time.

## Recent Decisions
List of recent decisions.

## Files Modified
Git diff summary.

## Git Status
Git status output.
```

---

### 6. Component Registry

**Location**: `.obsidient/registry/components.md`

**Schema**:
```yaml
## Component Name

- **Path**: filesystem path
- **Technology**: tech stack
- **Status**: active | deprecated | planned
- **Owner**: team name

### Entry Points
Key files to start with.

### Dependencies
Required services/components.

### Methods
- BMAD: usage description
- GSD: usage description
- Ralphe: usage description

### Obsidient Sync
What gets auto-logged.
```

---

### 7. Configuration

**Location**: `.obsidient/.obsidientrc`

**Schema** (YAML):
```yaml
obsidient_version: string    # Obsidient version
task_id_format: string       # Task ID format pattern
decision_id_format: string   # Decision ID format pattern
auto_archive_days: integer   # Days until auto-archive
max_active_tasks: integer    # Max concurrent active tasks

git_integration:
  enabled: boolean          # Enable git integration
  branch: string            # Target branch
  auto_commit: boolean      # Auto-commit changes

components: string[]        # List of valid components
```

---

## Auto-Generated Fields

### System-Generated
- `task_id`: Auto-incremented
- `decision_id`: Auto-incremented
- `created`: Auto-set on creation
- `updated`: Auto-updated on changes
- `session_id`: Auto-generated UUID
- `snapshot_id`: Unix timestamp

### Derived
- `status`: Derived from task location (active/completed/archived)
- `phase`: Updated by method router
- `method`: Updated by method router

---

## Relationships

```
Task 1:N Decision
  - A task can have many decisions
  - A decision belongs to one task (optional)

Task 1:N Context Snapshot
  - A task can have many snapshots
  - Each snapshot captures task state

Session 1:N Task
  - Session tracks multiple active tasks
  - One primary focus task

Component N:M Task
  - Tasks can affect multiple components
  - Components can have multiple tasks
```

---

## Validation Rules

### Task Validation
- `task_id` must match format `TASK-{3-digit}`
- `status` must be one of: active, completed, archived
- `phase` must be one of: analysis, planning, solutioning, implementation
- `method` must be one of: bmad, gsd, ralphe
- `created` and `updated` must be valid ISO8601

### Decision Validation
- `decision_id` must match format `DEC-{3-digit}`
- `status` must be one of: proposed, accepted, deprecated
- `date` must be valid ISO8601
- `task` must reference valid task (if present)

### Context Validation
- `session_id` must be non-empty
- `updated` must be valid ISO8601

---

## File Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Task (active) | `TASK-{seq}-{slug}.md` | `TASK-001-whatsapp-integration.md` |
| Task (completed) | `TASK-{seq}-{slug}.md` | `TASK-001-whatsapp-integration.md` |
| Task (archived) | `TASK-{seq}-{slug}.md` | `TASK-001-whatsapp-integration.md` |
| Decision | `DEC-{seq}-{slug}.md` | `DEC-001-whatsapp-api-choice.md` |
| Snapshot | `snap-{timestamp}.md` | `snap-1712234567.md` |

---

## Query Patterns

### Find Task by ID
```bash
grep -r "task_id: TASK-001" .obsidient/tasks/
```

### List All Active Tasks
```bash
ls .obsidient/tasks/active/
```

### Find Decisions for Task
```bash
grep -l "task: TASK-001" .obsidient/decisions/*.md
```

### Get Recent Snapshots
```bash
ls -lt .obsidient/context/snapshots/ | head -5
```

---

## Extensions

### Custom Frontmatter
You can add custom fields to frontmatter:

```yaml
---
task_id: TASK-001
custom_field: custom_value
priority: high
customer: ACME Corp
---
```

### Custom Sections
Add sections after the standard ones:

```markdown
## Objective
...

## Progress
...

## Custom Section
Your custom content here.
```

---

## Migration

### From Version 0.x to 1.0

1. Update frontmatter fields
2. Rename files to new convention
3. Move files to correct directories
4. Update configuration

### From Other Systems

1. Export existing data
2. Transform to Obsidient schema
3. Import to .obsidient/
4. Run validation

---

**Schema Version**: 1.0.0
**Last Updated**: 2026-04-04
