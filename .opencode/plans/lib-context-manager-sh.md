# Library: context-manager.sh

> **Purpose**: Manage shared context between BMAD, GSD, and Ralphe
> **File**: `lib/context-manager.sh`

---

## Full Implementation

```bash
#!/bin/bash
###############################################################################
# Context Manager - Shared context for all methods
###############################################################################

OBSIDIENT_DIR="${OBSIDIENT_DIR:-.obsidient}"
CONTEXT_DIR="$OBSIDIENT_DIR/context"
SESSION_FILE="$CONTEXT_DIR/current-session.md"

# Initialize context structure
init_context() {
    mkdir -p "$CONTEXT_DIR/snapshots"
    
    if [ ! -f "$SESSION_FILE" ]; then
        cat > "$SESSION_FILE" << 'EOF'
---
session_id: sess-init
created: 2026-04-04T00:00:00Z
updated: 2026-04-04T00:00:00Z
---

## Active Tasks

*No active tasks*

## Current Focus

Task: None
Component: None
Last Action: None

## Recent Context

*No recent activity*

## Cross-Task Context

*No shared context*
EOF
    fi
}

# Update session context
update_session_context() {
    local task_id="$1"
    local story_id="${2:-}"
    local component="${3:-}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Read task info
    local task_file=$(find "$OBSIDIENT_DIR/tasks" -name "${task_id}-*.md" | head -1)
    local task_title=""
    if [ -n "$task_file" ]; then
        task_title=$(grep "^title:" "$task_file" | cut -d'"' -f2)
    fi
    
    # Create new session content
    cat > "$SESSION_FILE" << EOF
---
session_id: sess-$(date +%s)
updated: $timestamp
---

## Active Tasks

$(list_active_tasks)

## Current Focus

Task: $task_id
Title: $task_title
Story: ${story_id:-None}
Component: ${component:-All}
Last Action: $(date)

## Recent Context

$(get_recent_context)

## Cross-Task Context

$(get_cross_task_context)
EOF

    # Create snapshot
    create_context_snapshot "$task_id"
}

# List active tasks for context
list_active_tasks() {
    local active_dir="$OBSIDIENT_DIR/tasks/active"
    
    if [ ! -d "$active_dir" ]; then
        echo "*No active tasks*"
        return
    fi
    
    local count=0
    for task in "$active_dir"/TASK-*.md; do
        [ -f "$task" ] || continue
        count=$((count + 1))
        
        local task_id=$(grep "^task_id:" "$task" | cut -d' ' -f2)
        local title=$(grep "^title:" "$task" | cut -d'"' -f2)
        local phase=$(grep "^phase:" "$task" | cut -d' ' -f2)
        local method=$(grep "^method:" "$task" | cut -d' ' -f2)
        
        echo "$count. **$task_id** - $title"
        echo "   Phase: $phase, Method: $method"
    done
    
    if [ $count -eq 0 ]; then
        echo "*No active tasks*"
    fi
}

# Get recent context from last operation
get_recent_context() {
    local last_action=$(grep "Last Action:" "$SESSION_FILE" 2>/dev/null | cut -d':' -f2- | xargs)
    
    if [ -n "$last_action" ] && [ "$last_action" != "None" ]; then
        echo "Previous: $last_action"
    else
        echo "*Starting fresh session*"
    fi
}

# Get cross-task context (shared components, dependencies)
get_cross_task_context() {
    # Analyze all active tasks and find shared components
    local active_dir="$OBSIDIENT_DIR/tasks/active"
    declare -A component_tasks
    
    if [ -d "$active_dir" ]; then
        for task in "$active_dir"/TASK-*.md; do
            [ -f "$task" ] || continue
            
            local task_id=$(grep "^task_id:" "$task" | cut -d' ' -f2)
            local components=$(grep "^  - " "$task" | sed 's/^  - //')
            
            for comp in $components; do
                if [ -n "${component_tasks[$comp]}" ]; then
                    component_tasks[$comp]="${component_tasks[$comp]}, $task_id"
                else
                    component_tasks[$comp]="$task_id"
                fi
            done
        done
    fi
    
    # Output shared components
    local has_shared=false
    for comp in "${!component_tasks[@]}"; do
        local tasks="${component_tasks[$comp]}"
        if [[ "$tasks" == *","* ]]; then
            echo "- $comp: $tasks"
            has_shared=true
        fi
    done
    
    if [ "$has_shared" = false ]; then
        echo "*No shared components*"
    fi
}

# Create context snapshot
create_context_snapshot() {
    local task_id="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local snapshot_file="$CONTEXT_DIR/snapshots/snap-$(date +%s).md"
    
    cat > "$snapshot_file" << EOF
---
snapshot_id: $(date +%s)
task: $task_id
timestamp: $timestamp
---

## Session State

$(cat "$SESSION_FILE")

## Task State

$(cat "$OBSIDIENT_DIR/tasks/active/${task_id}-"*.md 2>/dev/null || echo "Task not found")

## Recent Decisions

$(ls -1t "$OBSIDIENT_DIR/decisions"/*.md 2>/dev/null | head -5 | xargs cat 2>/dev/null)
EOF

    echo "Created snapshot: $snapshot_file"
}

# Restore context from snapshot
restore_context_snapshot() {
    local snapshot_id="$1"
    local snapshot_file="$CONTEXT_DIR/snapshots/snap-${snapshot_id}.md"
    
    if [ ! -f "$snapshot_file" ]; then
        echo "Error: Snapshot $snapshot_id not found"
        return 1
    fi
    
    # Extract session state
    sed -n '/## Session State/,/## Task State/p' "$snapshot_file" | tail -n +2 | head -n -1 > "$SESSION_FILE"
    
    echo "Restored context from snapshot: $snapshot_id"
}

# Get context for specific method
get_context_for_method() {
    local method="$1"
    
    case "$method" in
        bmad)
            # Return planning context
            grep -A 50 "## Active Tasks" "$SESSION_FILE" 2>/dev/null
            ;;
        ralphe|gsd)
            # Return implementation context
            grep -A 20 "## Current Focus" "$SESSION_FILE" 2>/dev/null
            grep -A 20 "## Recent Context" "$SESSION_FILE" 2>/dev/null
            ;;
        *)
            cat "$SESSION_FILE"
            ;;
    esac
}

# Update cross-method context
update_cross_method_context() {
    local from_method="$1"
    local to_method="$2"
    local context_data="$3"
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Add handoff note to session
    cat >> "$SESSION_FILE" << EOF

## Method Handoff [$timestamp]
From: $from_method
To: $to_method
Context: $context_data
EOF

    echo "Updated cross-method context: $from_method → $to_method"
}

# Show current context
show_session_context() {
    if [ -f "$SESSION_FILE" ]; then
        cat "$SESSION_FILE"
    else
        echo "No active session"
    fi
}

# Clear context (for new project)
clear_context() {
    local backup_file="$CONTEXT_DIR/session-backup-$(date +%s).md"
    
    if [ -f "$SESSION_FILE" ]; then
        mv "$SESSION_FILE" "$backup_file"
        echo "Backed up context to: $backup_file"
    fi
    
    init_context
    echo "Context cleared, new session initialized"
}

# Export context for external tools
export_context() {
    local format="${1:-json}"
    local output_file="${2:-$CONTEXT_DIR/export.}$format"
    
    case "$format" in
        json)
            # Convert markdown frontmatter to JSON
            cat "$SESSION_FILE" | awk '
                BEGIN { print "{" }
                /^---$/ { in_frontmatter = !in_frontmatter; next }
                in_frontmatter && /:/ { 
                    key = $1
                    gsub(/:/, "", key)
                    value = substr($0, index($0, ":") + 2)
                    printf "  \"%s\": \"%s\",\n", key, value
                }
                END { print "}" }
            ' > "$output_file"
            ;;
        yaml)
            cp "$SESSION_FILE" "$output_file"
            ;;
        *)
            echo "Unknown format: $format"
            return 1
            ;;
    esac
    
    echo "Exported context to: $output_file"
}

# Initialize on load
init_context
```

---

## Functions Summary

| Function | Purpose | Arguments |
|----------|---------|-----------|
| `init_context` | Initialize context files | - |
| `update_session_context` | Update current session | task_id, [story_id], [component] |
| `list_active_tasks` | List tasks for context | - |
| `get_recent_context` | Get recent activity | - |
| `get_cross_task_context` | Find shared components | - |
| `create_context_snapshot` | Backup context | task_id |
| `restore_context_snapshot` | Restore from backup | snapshot_id |
| `get_context_for_method` | Get method-specific context | method |
| `update_cross_method_context` | Log method handoff | from, to, data |
| `show_session_context` | Display context | - |
| `clear_context` | Reset context | - |
| `export_context` | Export to file | [format], [output] |

---

## Context File Structure

### current-session.md
```markdown
---
session_id: sess-1234567890
updated: 2026-04-04T14:45:00Z
---

## Active Tasks
1. **TASK-001** - WhatsApp Integration
   Phase: implementation, Method: ralphe
2. **TASK-002** - Admin Dashboard
   Phase: planning, Method: bmad

## Current Focus
Task: TASK-001
Title: WhatsApp Integration
Story: Story-05
Component: n8n/workflows
Last Action: ralphe run --story="Story-05"

## Recent Context
Previous: ralphe run completed 3 loops

## Cross-Task Context
- n8n: TASK-001 (active), TASK-002 (queued)

## Method Handoff [2026-04-04T14:30:00Z]
From: bmad
To: ralphe
Context: PRD approved, ready for implementation
```

---

## Usage Example

```bash
# Source libraries
source lib/obsidient-lib.sh
source lib/context-manager.sh

# Initialize
init_context

# Update context
update_session_context "TASK-001" "Story-05" "n8n/workflows"

# Get context for method
context=$(get_context_for_method "ralphe")
echo "$context"

# Create snapshot
create_context_snapshot "TASK-001"

# Show current state
show_session_context
```
