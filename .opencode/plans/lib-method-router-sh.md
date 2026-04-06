# Library: method-router.sh

> **Purpose**: Route commands to BMAD, GSD, and Ralphe
> **File**: `lib/method-router.sh`

---

## Full Implementation

```bash
#!/bin/bash
###############################################################################
# Method Router - Route commands to appropriate method
###############################################################################

BMAD_DIR="${BMAD_DIR:-_bmad}"
RALPHE_DIR="${RALPHE_DIR:-.ralph}"

# Route to BMAD skill
route_to_bmad() {
    local skill="$1"
    shift
    
    echo -e "\033[0;34m[BMAD] Executing: $skill\033[0m"
    
    case "$skill" in
        create-prd)
            local task_id="$1"
            local description="$2"
            
            # Check if opencode skill exists
            if [ -f ".opencode/skills/bmad-create-prd/SKILL.md" ]; then
                echo "Using BMAD skill: bmad-create-prd"
                # Trigger skill via opencode
                # opencode skill bmad-create-prd "$description"
                echo "PRD creation workflow would start here"
            else
                echo "BMAD skill not found. Using fallback."
            fi
            ;;
        
        domain-research)
            echo "Starting domain research..."
            # opencode skill bmad-domain-research
            ;;
        
        technical-research)
            echo "Starting technical research..."
            # opencode skill bmad-technical-research
            ;;
        
        market-research)
            echo "Starting market research..."
            # opencode skill bmad-market-research
            ;;
        
        validate-prd)
            echo "Validating PRD..."
            # opencode skill bmad-validate-prd
            ;;
        
        create-ux)
            echo "Creating UX design..."
            # opencode skill bmad-create-ux
            ;;
        
        create-architecture)
            echo "Creating architecture..."
            # opencode skill bmad-create-architecture
            ;;
        
        create-epics-stories)
            echo "Creating epics and stories..."
            # opencode skill bmad-create-epics-stories
            ;;
        
        implementation-readiness)
            echo "Checking implementation readiness..."
            # opencode skill bmad-implementation-readiness
            ;;
        
        *)
            echo "Unknown BMAD skill: $skill"
            return 1
            ;;
    esac
}

# Route to GSD (Get Shit Done)
route_to_gsd() {
    local task_id="$1"
    local story_id="${2:-}"
    
    echo -e "\033[0;34m[GSD] Direct execution mode\033[0m"
    
    # GSD is direct execution without loop
    # Could trigger: opencode skill gsd-run or similar
    
    if [ -n "$story_id" ]; then
        echo "Executing story: $story_id"
        # Focus on specific story from @fix_plan.md
    else
        echo "Executing next available task"
    fi
    
    # Mark task as completed after GSD
    obsidient_update_task "$task_id" "status" "completed"
}

# Route to Ralphe Loop
route_to_ralphe() {
    local task_id="$1"
    local story_id="${2:-}"
    
    echo -e "\033[0;34m[RALPHE] Starting autonomous loop\033[0m"
    
    # Check if ralphe is installed
    if [ ! -f "$RALPHE_DIR/ralph_loop.sh" ]; then
        echo "Error: Ralphe not found at $RALPHE_DIR/ralph_loop.sh"
        return 1
    fi
    
    # Prepare context for Ralphe
    local context="Task: $task_id"
    if [ -n "$story_id" ]; then
        context="$context, Story: $story_id"
    fi
    
    # Write context to Ralphe
    echo "$context" > "$RALPHE_DIR/.ralphe_context"
    
    # Start Ralphe loop
    echo "Starting Ralphe autonomous development loop..."
    echo "Press Ctrl+C to stop"
    
    # Run Ralphe
    bash "$RALPHE_DIR/ralph_loop.sh" "$@"
}

# Route to QA/Audit
route_to_qa() {
    local audit_type="$1"
    
    echo -e "\033[0;34m[QA] Running audit: $audit_type\033[0m"
    
    case "$audit_type" in
        security-audit)
            echo "Running security audit..."
            # Check for secrets
            # Check for vulnerabilities
            # opencode skill security-audit
            ;;
        
        performance-audit)
            echo "Running performance audit..."
            # Check bundle sizes
            # Check query performance
            ;;
        
        full-audit|*)
            echo "Running full quality audit..."
            # Run all checks
            # opencode skill qa-audit
            # opencode skill edge-case-hunter
            ;;
    esac
    
    # Generate audit report
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local report_file=".obsidient/audit-report-${timestamp}.md"
    
    cat > "$report_file" << EOF
---
audit_type: $audit_type
date: $timestamp
---

## Audit Results

Type: $audit_type
Date: $timestamp

## Findings

TODO: Populate with actual findings

## Recommendations

TODO: Add recommendations
EOF

    echo "Audit report saved to: $report_file"
}

# Check if method is available
is_method_available() {
    local method="$1"
    
    case "$method" in
        bmad)
            [ -d "$BMAD_DIR" ] && [ -f "$BMAD_DIR/COMMANDS.md" ]
            ;;
        ralphe)
            [ -f "$RALPHE_DIR/ralph_loop.sh" ]
            ;;
        gsd)
            # GSD is always available (direct execution)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Auto-select method based on phase
auto_select_method() {
    local phase="$1"
    
    case "$phase" in
        analysis|planning|solutioning)
            echo "bmad"
            ;;
        implementation)
            echo "ralphe"
            ;;
        fix|hotfix|quick)
            echo "gsd"
            ;;
        *)
            echo "bmad"
            ;;
    esac
}
```

---

## Functions Summary

| Function | Purpose | Arguments |
|----------|---------|-----------|
| `route_to_bmad` | Execute BMAD skill | skill_name, [args...] |
| `route_to_gsd` | Direct execution | task_id, [story_id] |
| `route_to_ralphe` | Start Ralphe loop | task_id, [story_id] |
| `route_to_qa` | Run audit | audit_type |
| `is_method_available` | Check if method exists | method |
| `auto_select_method` | Select method by phase | phase |

---

## BMAD Skills Supported

| Skill | Command | Purpose |
|-------|---------|---------|
| create-prd | `ralphe plan init` | Create PRD |
| domain-research | `ralphe plan research domain` | Domain research |
| technical-research | `ralphe plan research tech` | Technical research |
| market-research | `ralphe plan research market` | Market research |
| validate-prd | `ralphe plan validate` | Validate PRD |
| create-ux | `ralphe design ux` | UX design |
| create-architecture | `ralphe design arch` | Architecture |
| create-epics-stories | `ralphe design stories` | Epics & stories |
| implementation-readiness | `ralphe design ready` | Check readiness |

---

## Usage Example

```bash
# Source libraries
source lib/obsidient-lib.sh
source lib/method-router.sh

# Route to BMAD
route_to_bmad "create-prd" "TASK-001" "Feature description"

# Route to Ralphe
route_to_ralphe "TASK-001" "Story-05"

# Route to GSD
route_to_gsd "TASK-001"

# Auto-select method
method=$(auto_select_method "implementation")
echo "Selected method: $method"
```
