# Templates for Obsidient

> **Directory**: `.obsidient/templates/`

---

## 1. Task Template

**File**: `.obsidient/templates/task-template.md`

```markdown
---
task_id: {{TASK_ID}}
title: "{{TITLE}}"
status: active
phase: analysis
method: bmad
created: {{TIMESTAMP}}
updated: {{TIMESTAMP}}
components:
  - {{COMPONENT_1}}
  - {{COMPONENT_2}}
---

## Objective
{{DESCRIPTION}}

## Method History
<!-- AUTO-GENERATED: Records which commands were run -->

## Progress
<!-- AUTO-UPDATED: Progress checkboxes -->
- [ ] Initialize task

## Context
<!-- SHARED: All methods update this section -->

## Decisions Referenced
<!-- AUTO-UPDATED: Links to decisions -->

## Notes
<!-- Manual notes -->

## Resources
<!-- Links to specs, PRDs, etc. -->
```

### Usage
```bash
# From obsidient-lib.sh
obsidient_create_task() {
    local description="$1"
    local task_id="TASK-$(get_next_sequence)"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Read template and substitute
    sed -e "s/{{TASK_ID}}/$task_id/g" \
        -e "s/{{TITLE}}/$description/g" \
        -e "s/{{TIMESTAMP}}/$timestamp/g" \
        .obsidient/templates/task-template.md \
        > ".obsidient/tasks/active/${task_id}.md"
}
```

---

## 2. Decision Template

**File**: `.obsidient/templates/decision-template.md`

```markdown
---
decision_id: {{DECISION_ID}}
title: "{{TITLE}}"
date: {{TIMESTAMP}}
status: proposed
task: {{TASK_ID}}
---

## Context
What situation led to this decision?

## Problem Statement
What problem are we solving?

## Options Considered

### Option 1: {{OPTION_1}}
**Pros:**
- 

**Cons:**
- 

### Option 2: {{OPTION_2}}
**Pros:**
- 

**Cons:**
- 

## Decision
We will **{{CHOSEN_OPTION}}** because:

## Consequences

### Positive
- 

### Negative
- 

### Neutral
- 

## Related Decisions
- Link to related decisions

## References
- Links to documentation, discussions, etc.
```

### Usage
```bash
# From obsidient-lib.sh
obsidient_log_decision() {
    local task_id="$1"
    local title="$2"
    local decision_id="DEC-$(get_next_sequence)"
    
    sed -e "s/{{DECISION_ID}}/$decision_id/g" \
        -e "s/{{TITLE}}/$title/g" \
        -e "s/{{TASK_ID}}/$task_id/g" \
        -e "s/{{TIMESTAMP}}/$(date -u +%Y-%m-%dT%H:%M:%SZ)/g" \
        .obsidient/templates/decision-template.md \
        > ".obsidient/decisions/${decision_id}.md"
}
```

---

## 3. Audit Report Template

**File**: `.obsidient/templates/audit-template.md`

```markdown
---
audit_id: {{AUDIT_ID}}
type: {{TYPE}}
date: {{TIMESTAMP}}
task: {{TASK_ID}}
overall_status: pending
---

## Summary

| Category | Status | Issues |
|----------|--------|--------|
| Security | 🟡 | 2 warnings |
| Performance | 🟢 | 0 issues |
| Code Quality | 🟡 | 5 suggestions |
| Testing | 🔴 | 1 critical |

## Findings

### Critical
1. **{{ISSUE_1}}**
   - Location: `{{FILE_PATH}}`
   - Description: {{DESCRIPTION}}
   - Recommendation: {{RECOMMENDATION}}

### Warnings
1. **{{ISSUE_2}}**
   - Location: `{{FILE_PATH}}`
   - Description: {{DESCRIPTION}}
   - Recommendation: {{RECOMMENDATION}}

### Suggestions
1. **{{ISSUE_3}}**
   - Description: {{DESCRIPTION}}

## Recommendations

1. {{RECOMMENDATION_1}}
2. {{RECOMMENDATION_2}}

## Action Items

- [ ] Fix critical issue #1
- [ ] Address warnings
- [ ] Refactor suggested improvements
```

---

## 4. Context Snapshot Template

**File**: `.obsidient/templates/snapshot-template.md`

```markdown
---
snapshot_id: {{SNAPSHOT_ID}}
task: {{TASK_ID}}
timestamp: {{TIMESTAMP}}
trigger: {{TRIGGER}}
---

## Session State
{{SESSION_STATE}}

## Task State
{{TASK_STATE}}

## Recent Decisions
{{DECISIONS}}

## Files Modified (last hour)
{{FILE_CHANGES}}

## Git Status
{{GIT_STATUS}}
```

---

## 5. Component Registry Entry Template

**File**: `.obsidient/templates/component-entry.md`

```markdown
## {{COMPONENT_NAME}}

- **Path**: {{PATH}}
- **Technology**: {{TECH}}
- **Status**: {{STATUS}}
- **Owner**: {{OWNER}}

### Capabilities
- {{CAPABILITY_1}}
- {{CAPABILITY_2}}

### Entry Points
- {{ENTRY_1}}
- {{ENTRY_2}}

### Dependencies
- {{DEPENDENCY_1}}
- {{DEPENDENCY_2}}

### Methods
- BMAD: {{BMAD_USAGE}}
- GSD: {{GSD_USAGE}}
- Ralphe: {{RALPHE_USAGE}}

### Last Updated
{{TIMESTAMP}}
```

---

## 6. Method Handoff Template

**File**: `.obsidient/templates/handoff-template.md`

```markdown
---
handoff_id: {{HANDOFF_ID}}
from: {{FROM_METHOD}}
to: {{TO_METHOD}}
timestamp: {{TIMESTAMP}}
task: {{TASK_ID}}
---

## Deliverables Completed
<!-- What the source method completed -->
- [ ] {{DELIVERABLE_1}}
- [ ] {{DELIVERABLE_2}}

## Context Summary
<!-- Key information for the receiving method -->
{{CONTEXT}}

## Blockers
<!-- Any blockers or dependencies -->
{{BLOCKERS}}

## Next Steps
<!-- What the receiving method should do -->
1. {{STEP_1}}
2. {{STEP_2}}

## Resources
<!-- Links to relevant files -->
- {{RESOURCE_1}}
- {{RESOURCE_2}}

## Questions?
<!-- Open questions for discussion -->
{{QUESTIONS}}
```

---

## Template Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `{{TASK_ID}}` | Task identifier | TASK-001 |
| `{{DECISION_ID}}` | Decision identifier | DEC-001 |
| `{{TITLE}}` | Task/decision title | WhatsApp Integration |
| `{{TIMESTAMP}}` | ISO 8601 timestamp | 2026-04-04T14:45:00Z |
| `{{COMPONENT_*}}` | Component name | n8n/workflows |
| `{{DESCRIPTION}}` | Full description | Implement ordering... |
| `{{STATUS}}` | Current status | active, completed |
| `{{PHASE}}` | Development phase | analysis, implementation |
| `{{METHOD}}` | Current method | bmad, ralphe, gsd |

---

## Template Processing Script

**File**: `lib/template-processor.sh`

```bash
#!/bin/bash

process_template() {
    local template_file="$1"
    local output_file="$2"
    shift 2
    
    # Copy template to output
    cp "$template_file" "$output_file"
    
    # Process key-value pairs
    while [[ $# -gt 0 ]]; do
        local key="$1"
        local value="$2"
        shift 2
        
        # Escape special characters for sed
        value=$(echo "$value" | sed 's/[&/\]/\\&/g')
        
        # Replace in file
        sed -i "s/{{$key}}/$value/g" "$output_file"
    done
    
    echo "Template processed: $output_file"
}

# Usage
# process_template \
#     .obsidient/templates/task-template.md \
#     .obsidient/tasks/active/TASK-001.md \
#     "TASK_ID" "TASK-001" \
#     "TITLE" "My Task" \
#     "TIMESTAMP" "2026-04-04T14:45:00Z"
```
