# Library: obsidient-lib.sh

> **Purpose**: Core read/write functions for Obsidient knowledge base
> **File**: `lib/obsidient-lib.sh`

---

## Full Implementation

```bash
#!/bin/bash
###############################################################################
# Obsidient Library - Read/Write functions for knowledge base
###############################################################################

OBSIDIENT_DIR="${OBSIDIENT_DIR:-.obsidient}"
CONFIG_FILE="$OBSIDIENT_DIR/.obsidientrc"

# Initialize sequence counter
init_sequence() {
    local seq_file="$OBSIDIENT_DIR/.sequence"
    if [ ! -f "$seq_file" ]; then
        echo "0" > "$seq_file"
    fi
}

# Get next sequence number
get_next_sequence() {
    local seq_file="$OBSIDIENT_DIR/.sequence"
    local seq=$(cat "$seq_file" 2>/dev/null || echo "0")
    seq=$((seq + 1))
    echo "$seq" > "$seq_file"
    printf "%03d" "$seq"
}

# Create new task
obsidient_create_task() {
    local description="$1"
    local task_id="TASK-$(get_next_sequence)"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Generate filename-friendly version
    local filename_desc=$(echo "$description" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | cut -c1-50)
    local task_file="$OBSIDIENT_DIR/tasks/active/${task_id}-${filename_desc}.md"
    
    cat > "$task_file" << EOF
---
task_id: $task_id
title: "$description"
status: active
phase: analysis
method: bmad
created: $timestamp
updated: $timestamp
components: []
---

## Objective
$description

## Method History
<!-- AUTO-GENERATED - Do not edit manually -->

## Progress
- [ ] Initialize task

## Context
<!-- SHARED CONTEXT - Updated by all methods -->

## Decisions Referenced

## Notes
EOF

    # Set as active task
    echo "$task_id" > "$OBSIDIENT_DIR/.active_task"
    
    # Update dashboard
    update_dashboard
    
    echo "$task_id"
}

# Update task field
obsidient_update_task() {
    local task_id="$1"
    local field="$2"
    local value="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local task_file=$(find "$OBSIDIENT_DIR/tasks" -name "${task_id}-*.md" | head -1)
    
    if [ -z "$task_file" ]; then
        echo "Error: Task $task_id not found" >&2
        return 1
    fi
    
    # Update the field in frontmatter
    case "$field" in
        phase|method|status)
            sed -i "s/^$field: .*/$field: $value/" "$task_file"
            ;;
        *)
            # For other fields, add to context section
            ;;
    esac
    
    # Update timestamp
    sed -i "s/^updated: .*/updated: $timestamp/" "$task_file"
    
    update_dashboard
}

# Log decision
obsidient_log_decision() {
    local task_id="$1"
    local decision="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local decision_id="DEC-$(get_next_sequence)"
    
    cat > "$OBSIDIENT_DIR/decisions/${decision_id}.md" << EOF
---
decision_id: $decision_id
task: $task_id
date: $timestamp
status: accepted
---

## Context
Decision made during $task_id

## Decision
$decision

## Rationale

## Consequences
EOF

    # Add reference to task
    local task_file=$(find "$OBSIDIENT_DIR/tasks" -name "${task_id}-*.md" | head -1)
    if [ -n "$task_file" ]; then
        sed -i "/## Decisions Referenced/a\- [$decision_id] $decision" "$task_file"
    fi
}

# Get active task
obsidient_get_active_task() {
    if [ -f "$OBSIDIENT_DIR/.active_task" ]; then
        cat "$OBSIDIENT_DIR/.active_task"
    fi
}

# Set active task
obsidient_set_active_task() {
    local task_id="$1"
    echo "$task_id" > "$OBSIDIENT_DIR/.active_task"
    
    local task_file=$(find "$OBSIDIENT_DIR/tasks" -name "${task_id}-*.md" | head -1)
    if [ -z "$task_file" ]; then
        echo "Error: Task $task_id not found" >&2
        return 1
    fi
    
    update_dashboard
}

# List tasks by status
obsidient_list_tasks() {
    local status="$1"
    local dir="$OBSIDIENT_DIR/tasks/$status"
    
    if [ -d "$dir" ]; then
        for task in "$dir"/TASK-*.md; do
            [ -f "$task" ] || continue
            local task_id=$(grep "^task_id:" "$task" | cut -d' ' -f2)
            local title=$(grep "^title:" "$task" | cut -d'"' -f2)
            local phase=$(grep "^phase:" "$task" | cut -d' ' -f2)
            echo "  $task_id - $title ($phase)"
        done
    fi
}

# List all tasks
obsidient_list_all_tasks() {
    for status in active completed archived; do
        echo -e "\n${status}:"
        obsidient_list_tasks "$status"
    done
}

# Archive task
obsidient_archive_task() {
    local task_id="$1"
    local task_file=$(find "$OBSIDIENT_DIR/tasks/active" -name "${task_id}-*.md" | head -1)
    
    if [ -z "$task_file" ]; then
        echo "Error: Task $task_id not found in active" >&2
        return 1
    fi
    
    # Update status
    sed -i 's/^status: .*/status: archived/' "$task_file"
    
    # Move to archived
    mv "$task_file" "$OBSIDIENT_DIR/tasks/archived/"
    
    update_dashboard
}

# Sync task progress from Ralphe
obsidient_sync_task_progress() {
    local task_id="$1"
    local ralph_dir=".ralph"
    
    # Read Ralphe status
    if [ -f "$ralph_dir/status.json" ]; then
        local status=$(jq -r '.status' "$ralph_dir/status.json" 2>/dev/null)
        local loop_count=$(jq -r '.loop_count' "$ralph_dir/status.json" 2>/dev/null)
        
        # Update task file
        local task_file=$(find "$OBSIDIENT_DIR/tasks" -name "${task_id}-*.md" | head -1)
        if [ -n "$task_file" ]; then
            # Add to method history
            local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            sed -i "/## Method History/a\- **ralphe-loop** → Status: $status, Loops: $loop_count [$timestamp]" "$task_file"
            
            # Update timestamp
            sed -i "s/^updated: .*/updated: $timestamp/" "$task_file"
        fi
    fi
    
    # Read fix_plan progress
    if [ -f "$ralph_dir/@fix_plan.md" ]; then
        local completed=$(grep -c "^\s*- \[x\]" "$ralph_dir/@fix_plan.md" 2>/dev/null || echo "0")
        local total=$(grep -c "^\s*- \[\s*\]" "$ralph_dir/@fix_plan.md" 2>/dev/null || echo "0")
        total=$((completed + total))
        
        # Update progress section
        local task_file=$(find "$OBSIDIENT_DIR/tasks" -name "${task_id}-*.md" | head -1)
        if [ -n "$task_file" ]; then
            sed -i "/## Context/a\\n## Ralphe Progress\nCompleted: $completed/$total stories" "$task_file"
        fi
    fi
    
    update_dashboard
}

# Log audit results
obsidient_log_audit() {
    local task_id="$1"
    local audit_type="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local task_file=$(find "$OBSIDIENT_DIR/tasks" -name "${task_id}-*.md" | head -1)
    if [ -n "$task_file" ]; then
        sed -i "/## Method History/a\- **audit-$audit_type** → Completed [$timestamp]" "$task_file"
    fi
}

# Update dashboard README
update_dashboard() {
    local active_count=$(find "$OBSIDIENT_DIR/tasks/active" -name "TASK-*.md" 2>/dev/null | wc -l)
    local completed_count=$(find "$OBSIDIENT_DIR/tasks/completed" -name "TASK-*.md" 2>/dev/null | wc -l)
    local archived_count=$(find "$OBSIDIENT_DIR/tasks/archived" -name "TASK-*.md" 2>/dev/null | wc -l)
    local decision_count=$(find "$OBSIDIENT_DIR/decisions" -name "DEC-*.md" 2>/dev/null | wc -l)
    
    cat > "$OBSIDIENT_DIR/README.md" << EOF
# Obsidient Knowledge Base

> **The Single Source of Truth** for Ralphé Unified System
> 
> Last updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

---

## Quick Status

| Metric | Count |
|--------|-------|
| **Active Tasks** | $active_count |
| **Completed Tasks** | $completed_count |
| **Archived Tasks** | $archived_count |
| **Decisions** | $decision_count |

---

## Active Tasks

$(obsidient_list_tasks "active")

---

## Quick Commands

\`\`\`bash
# Plan Phase (BMAD)
ralphe plan init "Feature description"
ralphe plan research domain

# Design Phase (BMAD)
ralphe design ux
ralphe design arch

# Execution (Ralphe/GSD)
ralphe run
ralphe run --gsd

# Quality
ralphe audit

# Management
ralphe status
ralphe list
\`\`\`

---

*Auto-generated by Ralphé Unified System*
EOF
}

# Initialize
init_sequence
```

---

## Functions Summary

| Function | Purpose | Arguments |
|----------|---------|-----------|
| `obsidient_create_task` | Create new task | description |
| `obsidient_update_task` | Update task field | task_id, field, value |
| `obsidient_log_decision` | Record decision | task_id, decision |
| `obsidient_get_active_task` | Get current task | - |
| `obsidient_set_active_task` | Switch task | task_id |
| `obsidient_list_tasks` | List tasks by status | status |
| `obsidient_list_all_tasks` | List all tasks | - |
| `obsidient_archive_task` | Archive completed | task_id |
| `obsidient_sync_task_progress` | Sync from Ralphe | task_id |
| `obsidient_log_audit` | Log audit results | task_id, type |
| `update_dashboard` | Regenerate README | - |

---

## Usage Example

```bash
# Source the library
source lib/obsidient-lib.sh

# Create a task
task_id=$(obsidient_create_task "WhatsApp integration")

# Update phase
obsidient_update_task "$task_id" "phase" "implementation"

# Log decision
obsidient_log_decision "$task_id" "Use WhatsApp Business API"

# Sync from Ralphe
obsidient_sync_task_progress "$task_id"
```
