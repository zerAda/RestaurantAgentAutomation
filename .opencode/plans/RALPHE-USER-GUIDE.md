# Ralphé Unified System - User Guide

> **Version**: 1.0.0
> **Created**: 2026-04-04

---

## What is Ralphé Unified System?

**Ralphé** unifies three development methodologies into one cohesive workflow:

| Method | Purpose | When to Use |
|--------|---------|-------------|
| **BMAD** | Planning & Analysis | New features, architecture decisions |
| **GSD** | Direct Execution | Quick fixes, hotfixes, simple tasks |
| **Ralphe Loop** | Autonomous Development | Complex implementation, refactoring |

**Obsidient** maintains shared knowledge across all methods.

---

## Quick Start

### 1. Initialize the System

```bash
# Create the system (one-time setup)
./ralphe system init

# Verify installation
./ralphe system verify
```

### 2. Create Your First Task

```bash
# Plan a new feature
ralphe plan init "WhatsApp ordering integration"

# Check status
ralphe status
```

### 3. Work Through Phases

```bash
# Phase 1: Planning (BMAD)
ralphe plan research domain
ralphe plan research tech

# Phase 2: Design (BMAD)
ralphe design ux
ralphe design arch
ralphe design stories

# Phase 3: Implementation (Ralphe)
ralphe run

# Or quick fix (GSD)
ralphe run --gsd
```

### 4. Quality Check

```bash
# Run audit
ralphe audit
```

---

## Command Reference

### Planning Commands (BMAD)

```bash
ralphe plan init "<description>"      # Create new task
ralphe plan research domain           # Domain research
ralphe plan research tech             # Technical research
ralphe plan research market           # Market research
ralphe plan validate                  # Validate PRD
```

### Design Commands (BMAD)

```bash
ralphe design ux                      # UX design
ralphe design arch                    # Architecture design
ralphe design stories                 # Epics & stories
ralphe design ready                   # Check readiness
```

### Execution Commands

```bash
ralphe run                            # Start Ralphe loop
ralphe run --gsd                      # GSD direct execution
ralphe run --story="Story-05"         # Specific story
ralphe run --component=n8n            # Component focus
```

### Quality Commands

```bash
ralphe audit                          # Full audit
ralphe audit security                 # Security audit
ralphe audit performance              # Performance audit
```

### Management Commands

```bash
ralphe status                         # Show dashboard
ralphe list                           # List all tasks
ralphe switch TASK-001                # Change active task
ralphe archive TASK-001               # Archive task
```

### System Commands

```bash
ralphe system init                    # Initialize system
ralphe system verify                  # Verify installation
ralphe system migrate                 # Migrate existing tasks
```

---

## Workflow Examples

### Example 1: New Feature Development

```bash
# 1. Initialize
ralphe plan init "Customer loyalty program"

# 2. Research
ralphe plan research domain
ralphe plan research tech

# 3. Design
ralphe design ux
ralphe design arch
ralphe design stories

# 4. Check readiness
ralphe design ready

# 5. Implement
ralphe run

# 6. Audit
ralphe audit

# 7. Complete
ralphe archive TASK-001
```

### Example 2: Quick Bug Fix

```bash
# 1. Switch to relevant task (or create new)
ralphe switch TASK-003

# 2. Quick fix with GSD
ralphe run --gsd

# 3. Verify
ralphe audit

# 4. Done
```

### Example 3: Multi-Task Management

```bash
# See all tasks
ralphe list

# Output:
# active:
#   TASK-001 - WhatsApp integration (implementation)
#   TASK-002 - Admin dashboard v2 (planning)
# completed:
#   TASK-000 - System setup (completed)

# Switch between tasks
ralphe switch TASK-002
ralphe design ux

ralphe switch TASK-001
ralphe run --story="Story-03"
```

---

## Understanding Obsidient

### What Gets Tracked?

1. **Tasks**: All work items with progress
2. **Decisions**: Architecture & design choices
3. **Context**: Shared knowledge between methods
4. **Snapshots**: Historical backups

### Directory Structure

```
.obsidient/
├── tasks/
│   ├── active/           # Current work
│   ├── completed/        # Done
│   └── archived/         # Old (auto-archived)
├── decisions/            # DEC-001, DEC-002...
├── context/
│   ├── current-session.md    # Active context
│   ├── project-state.md      # Overall status
│   └── snapshots/            # Backups
├── registry/
│   ├── components.md     # Component definitions
│   ├── capabilities.md   # Available methods
│   └── integrations.md   # Integration mappings
└── templates/            # Reusable templates
```

### Auto-Commit to Git

By default, Obsidient auto-commits changes:

```bash
# Commit format:
[obsidient] <action>: <target>

# Examples:
[obsidient] task-create: TASK-001
[obsidient] task-update: TASK-001
[obsidient] decision: DEC-003
```

Configure in `.obsidient/.obsidientrc`:

```yaml
git_integration:
  enabled: true
  branch: main
  auto_commit: true
```

---

## Method Selection Guide

### When to Use BMAD?

✅ **Use BMAD for:**
- New features requiring planning
- Architecture decisions
- UX design
- Technical research
- Sprint planning

❌ **Don't use BMAD for:**
- Quick bug fixes
- Simple text changes
- Emergency hotfixes

### When to Use GSD?

✅ **Use GSD for:**
- Quick fixes (< 30 min)
- Emergency hotfixes
- Configuration changes
- Documentation updates
- Simple refactors

❌ **Don't use GSD for:**
- Complex features
- Architecture changes
- Multi-file refactors

### When to Use Ralphe Loop?

✅ **Use Ralphe for:**
- Complex implementation
- Multi-story features
- Refactoring
- Test generation
- Code reviews

❌ **Don't use Ralphe for:**
- Quick tasks (overhead too high)
- Planning (use BMAD)
- Emergency fixes (use GSD)

---

## Cross-Component Work

All methods can work across any component:

### n8n Workflows

```bash
# Plan workflow
ralphe design arch --component=n8n

# Implement workflow
ralphe run --component=n8n
```

### Admin Dashboard

```bash
# UX design
ralphe design ux --component=admin-dashboard

# Implement feature
ralphe run --component=admin-dashboard
```

### Strapi Backend

```bash
# API design
ralphe design arch --component=strapi-backend

# Implement API
ralphe run --component=strapi-backend
```

---

## Troubleshooting

### Issue: "No active task"

```bash
# Create a task first
ralphe plan init "Task description"

# Or switch to existing task
ralphe switch TASK-001
```

### Issue: "Method not found"

```bash
# Verify installation
ralphe system verify

# Check if BMAD/Ralphe are installed
ls -la _bmad/
ls -la .ralph/
```

### Issue: "Git commit failed"

```bash
# Check git status
git status

# Ensure you're on main branch
git checkout main

# Or disable auto-commit
# Edit .obsidient/.obsidientrc:
# git_integration:
#   auto_commit: false
```

### Issue: "Ralphe loop not starting"

```bash
# Check Ralphe installation
ls -la .ralph/ralph_loop.sh

# Check configuration
cat .ralph/.ralphrc

# Reset and try again
ralphe run --reset
```

---

## Best Practices

### 1. One Task at a Time

Focus on one active task. Use `ralphe switch` to change context.

### 2. Document Decisions

Important decisions are auto-logged. Review them:

```bash
ls -la .obsidient/decisions/
```

### 3. Regular Snapshots

Context snapshots are auto-created. Restore if needed:

```bash
# List snapshots
ls -la .obsidient/context/snapshots/

# Restore (manual for now)
cp .obsidient/context/snapshots/snap-XXX.md .obsidient/context/current-session.md
```

### 4. Archive Completed Work

Keep active list clean:

```bash
ralphe archive TASK-001
```

### 5. Review Dashboard Regularly

```bash
ralphe status
```

---

## Advanced Usage

### Custom Configuration

Edit `.obsidient/.obsidientrc`:

```yaml
obsidient_version: "1.0.0"
task_id_format: "TASK-{seq:03d}"
auto_archive_days: 7
max_active_tasks: 5

git_integration:
  enabled: true
  branch: main
  auto_commit: true

components:
  - n8n/workflows
  - admin-dashboard
  - kiosk-app
  - strapi-backend
  - infrastructure
```

### Export Context

```bash
# Export to JSON
source lib/context-manager.sh
export_context json context-export.json

# Export to YAML
export_context yaml context-export.yaml
```

### Manual Context Update

```bash
# Edit context directly
vi .obsidient/context/current-session.md

# Update from Ralphe
source lib/obsidient-lib.sh
obsidient_sync_task_progress TASK-001
```

---

## Migration from Existing Setup

If you have existing `.ralph/` tasks:

```bash
# Migrate to Obsidient
ralphe system migrate

# This will:
# - Import .ralph/@fix_plan.md tasks
# - Create Obsidient task files
# - Preserve context
```

---

## Support

### Documentation
- This guide: `docs/RALPHE-UNIFIED.md`
- Schema reference: `docs/OBSIDIENT-SCHEMA.md`
- Implementation plan: `.opencode/plans/IMPLEMENTATION-PLAN.md`

### Commands
- `ralphe --help`: Show help
- `ralphe --version`: Show version

### Troubleshooting
- Check `ralphe system verify`
- Review `.obsidient/README.md` (dashboard)
- Check git logs for auto-commits

---

## Roadmap

### v1.1 (Planned)
- [ ] Web dashboard for Obsidient
- [ ] Real-time sync between team members
- [ ] Integration with project management tools

### v1.2 (Planned)
- [ ] AI-powered context suggestions
- [ ] Automatic method selection
- [ ] Performance analytics

---

**Happy coding with Ralphé Unified System! 🚀**
