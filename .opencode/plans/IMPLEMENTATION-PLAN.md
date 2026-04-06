# Ralphé Unified System - Implementation Plan

> **Status**: In Progress
> **Created**: 2026-04-04
> **Version**: 1.0.0

---

## ✅ COMPLETED

### Phase 1: Directory Structure
- [x] `.obsidient/tasks/active/`
- [x] `.obsidient/tasks/completed/`
- [x] `.obsidient/tasks/archived/`
- [x] `.obsidient/decisions/`
- [x] `.obsidient/context/snapshots/`
- [x] `.obsidient/registry/`
- [x] `.obsidient/templates/`
- [x] `lib/`
- [x] `docs/`

---

## 🔄 REMAINING WORK

### Phase 2: Core Files to Create (18 total)

#### 2.1 Main Wrapper Script
**File**: `ralphe` (in project root)
```bash
#!/bin/bash
# Main entry point for Ralphé Unified System
# Routes commands to BMAD/GSD/Ralphe and syncs to Obsidient
```

**Key Features**:
- Command parsing and routing
- Obsidient integration
- Git auto-commit
- Context management

#### 2.2 Library Files
**Directory**: `lib/`

1. **obsidient-lib.sh** - Read/write functions for Obsidient
2. **method-router.sh** - Command routing logic
3. **git-sync.sh** - Git auto-commit functionality
4. **context-manager.sh** - Shared context management

#### 2.3 Configuration Files
**Directory**: `.obsidient/`

1. **.obsidientrc** - Obsidient configuration
2. **README.md** - Dashboard/overview

#### 2.4 Context Files
**Directory**: `.obsidient/context/`

1. **current-session.md** - Shared session context
2. **project-state.md** - Overall project status

#### 2.5 Registry Files
**Directory**: `.obsidient/registry/`

1. **components.md** - Component registry
2. **capabilities.md** - Available methods/actions
3. **integrations.md** - Cross-component mappings

#### 2.6 Templates
**Directory**: `.obsidient/templates/`

1. **task-template.md** - New task template
2. **decision-template.md** - Decision record template

#### 2.7 Initial Task
**Directory**: `.obsidient/tasks/active/`

1. **TASK-000-system-init.md** - First task to initialize the system

#### 2.8 Documentation
**Directory**: `docs/` or `.opencode/plans/`

1. **RALPHE-UNIFIED.md** - User guide
2. **OBSIDIENT-SCHEMA.md** - Data structure reference

---

## 📋 IMPLEMENTATION CHECKLIST

### Step 1: Create Configuration
- [ ] `.obsidient/.obsidientrc`
- [ ] `.obsidient/README.md`

### Step 2: Create Library Functions
- [ ] `lib/obsidient-lib.sh`
- [ ] `lib/method-router.sh`
- [ ] `lib/git-sync.sh`
- [ ] `lib/context-manager.sh`

### Step 3: Create Templates
- [ ] `.obsidient/templates/task-template.md`
- [ ] `.obsidient/templates/decision-template.md`

### Step 4: Create Registry
- [ ] `.obsidient/registry/components.md`
- [ ] `.obsidient/registry/capabilities.md`
- [ ] `.obsidient/registry/integrations.md`

### Step 5: Create Initial Context
- [ ] `.obsidient/context/current-session.md`
- [ ] `.obsidient/context/project-state.md`

### Step 6: Create Main Wrapper
- [ ] `ralphe` (executable script)

### Step 7: Initialize System
- [ ] `.obsidient/tasks/active/TASK-000-system-init.md`

### Step 8: Create Documentation
- [ ] `docs/RALPHE-UNIFIED.md`
- [ ] `docs/OBSIDIENT-SCHEMA.md`

---

## 🚀 COMMAND REFERENCE (Target State)

### Planning (BMAD)
```bash
ralphe plan init "Description"      # Create task + run bmad-create-prd
ralphe plan research domain         # bmad-domain-research
ralphe plan research tech           # bmad-technical-research
ralphe plan validate                # bmad-validate-prd
```

### Design (BMAD)
```bash
ralphe design ux                    # bmad-create-ux
ralphe design arch                  # bmad-create-architecture
ralphe design stories               # bmad-create-epics-stories
ralphe design ready                 # bmad-implementation-readiness
```

### Execution (Ralphe/GSD)
```bash
ralphe run                          # Start ralphe-loop
ralphe run --gsd                    # Direct execution
ralphe run --story="Story-05"       # Specific story
ralphe run --component=n8n          # Component filter
```

### Quality
```bash
ralphe audit                        # Full audit
ralphe audit security               # Security focus
ralphe audit performance            # Performance focus
```

### Management
```bash
ralphe status                       # Show dashboard
ralphe list                         # List all tasks
ralphe switch TASK-001              # Change active task
ralphe archive TASK-001             # Archive task
```

---

## 🔄 OBSIDIENT SYNC PROTOCOL

### After BMAD Commands
- Create/update task file
- Log decisions to `decisions/`
- Update `current-session.md`
- Commit to git (if enabled)

### After Ralphe/GSD Commands
- Update task progress
- Log files modified
- Update context snapshots
- Sync `current-session.md`

### After Audit Commands
- Log audit results
- Update task quality gates
- Create remediation tasks if needed

---

## 📁 FILE TEMPLATES

### Task Template Structure
```markdown
---
task_id: TASK-XXX
title: "Task Title"
status: active|completed|archived
phase: analysis|planning|solutioning|implementation
method: bmad|gsd|ralphe
created: ISO8601
updated: ISO8601
components: []
---

## Objective
Brief description

## Method History
1. **command** → result [timestamp]

## Progress
- [ ] Item 1
- [x] Item 2

## Shared Context
Current state, blocks, notes
```

### Decision Template Structure
```markdown
---
decision_id: DEC-XXX
title: "Decision Title"
date: ISO8601
status: proposed|accepted|deprecated
task: TASK-XXX
---

## Context
What led to this decision

## Options Considered
1. Option A - pros/cons
2. Option B - pros/cons

## Decision
Chosen option + rationale

## Consequences
Impact on project
```

---

## ⚠️ IMPLEMENTATION NOTES

### Security Restrictions
Current file write restrictions:
- ✅ Can write to: `.opencode/plans/*.md`
- ✅ Can write to: `../../.local/share/opencode/plans/*.md`
- ❌ Cannot write to project root or other directories

### Solution Options
1. **User lifts restrictions** - Grant write access to full project
2. **Manual creation** - Provide files for user to create manually
3. **Alternative path** - Store system in allowed path only

### Recommendation
Implement as much as possible in allowed paths, then request permission to write to project directories.

---

## 🎯 NEXT STEPS

1. **Option A**: Request user to lift file restrictions
2. **Option B**: Create files manually using provided templates
3. **Option C**: Implement in `.opencode/plans/` only

**Recommended**: Option A - Full integration requires unrestricted access

---

*Plan generated by Ralphé Unified System*
*Last updated: 2026-04-04T22:00:00Z*
