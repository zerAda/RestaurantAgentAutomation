# Registry: Capabilities

> **File**: `.obsidient/registry/capabilities.md`
> **Purpose**: Available methods and their capabilities

---

## BMAD Capabilities

### Analysis Phase

| Capability | Command | Description | Output |
|------------|---------|-------------|--------|
| Create Brief | `bmad-create-brief` | Define product idea | Product Brief |
| Domain Research | `bmad-domain-research` | Industry deep dive | Research Report |
| Market Research | `bmad-market-research` | Competitive analysis | Market Report |
| Technical Research | `bmad-technical-research` | Feasibility study | Tech Report |
| Validate Brief | `bmad-validate-brief` | Verify brief quality | Validation Report |

### Planning Phase

| Capability | Command | Description | Output |
|------------|---------|-------------|--------|
| Create PRD | `bmad-create-prd` | Product requirements | PRD Document |
| Create UX | `bmad-create-ux` | UX design | UX Spec |
| Edit PRD | `bmad-edit-prd` | Modify PRD | Updated PRD |
| Validate PRD | `bmad-validate-prd` | Check PRD quality | Validation Report |
| Validate UX | `bmad-validate-ux` | Check UX design | Validation Report |

### Solutioning Phase

| Capability | Command | Description | Output |
|------------|---------|-------------|--------|
| Create Architecture | `bmad-create-architecture` | Technical design | ARCH Document |
| Create Epics/Stories | `bmad-create-epics-stories` | Sprint planning | Stories List |
| Validate Architecture | `bmad-validate-architecture` | Check design | Validation Report |
| Validate Stories | `bmad-validate-epics-stories` | Check stories | Validation Report |
| Implementation Readiness | `bmad-implementation-readiness` | Pre-impl check | Readiness Report |

### Implementation Phase

| Capability | Command | Description | Output |
|------------|---------|-------------|--------|
| Sprint Planning | `bmad-sprint-planning` | Plan sprint | Sprint Plan |
| Create Story | `bmad-create-story` | Prepare story | Story Spec |
| Validate Story | `bmad-validate-story` | Verify story | Validation Report |
| Sprint Status | `bmad-sprint-status` | Check progress | Status Report |
| Retrospective | `bmad-retrospective` | Review sprint | Retro Notes |
| QA Automate | `bmad-qa-automate` | Generate tests | Test Suite |

### Utilities

| Capability | Command | Description | Output |
|------------|---------|-------------|--------|
| Brainstorm | `bmad-brainstorm-project` | Generate ideas | Idea List |
| Document Project | `bmad-document-project` | Analyze codebase | Documentation |
| Generate Context | `bmad-generate-project-context` | Create context file | Context.md |
| Quick Dev | `bmad-quick-dev` | Quick implementation | Code |
| Tech Spec | `bmad-tech-spec` | Technical spec | Spec Document |
| Index Docs | `bmad-index-docs` | Document organization | Index |
| Distillator | `bmad-distillator` | Summarize content | Summary |
| Edge Case Hunter | `bmad-edge-case-hunter` | Find edge cases | Edge Case List |
| Adversarial Review | `bmad-adversarial-review` | Critical review | Review Report |
| Advanced Elicitation | `bmad-advanced-elicitation` | Requirements gathering | Requirements |

---

## GSD (Get Shit Done) Capabilities

| Capability | Command | Description | Use Case |
|------------|---------|-------------|----------|
| Direct Execute | `gsd-run` | Execute without loop | Quick fixes |
| Hotfix | `gsd-run --hotfix` | Emergency fix | Production issues |
| Quick Edit | `gsd-run --edit` | File modification | Simple changes |
| Debug | `gsd-run --debug` | Troubleshoot | Debug session |

---

## Ralphe Loop Capabilities

| Capability | Command | Description | Use Case |
|------------|---------|-------------|----------|
| Autonomous Loop | `ralphe run` | Continuous development | Feature implementation |
| Story Focus | `ralphe run --story=<id>` | Specific story | Targeted work |
| Component Focus | `ralphe run --component=<name>` | Component scope | Narrow focus |
| Review Mode | `ralphe run --review` | With code review | Quality focus |
| Live Mode | `ralphe run --live` | Real-time streaming | Monitoring |
| Reset | `ralphe run --reset` | Fresh start | New session |

---

## QA/Audit Capabilities

| Capability | Command | Description | Output |
|------------|---------|-------------|--------|
| Full Audit | `qa-audit` | Complete quality check | Audit Report |
| Security Audit | `qa-audit --security` | Security review | Security Report |
| Performance Audit | `qa-audit --performance` | Performance check | Performance Report |
| Code Review | `qa-review` | Peer review | Review Comments |
| Test Generation | `qa-automate` | Auto-generate tests | Test Suite |

---

## Obsidient Capabilities

| Capability | Command | Description | Output |
|------------|---------|-------------|--------|
| Create Task | `ralphe plan init` | New task | Task File |
| Update Task | (auto) | Sync progress | Updated Task |
| Log Decision | (auto) | Record decision | Decision File |
| Create Snapshot | (auto) | Context backup | Snapshot File |
| List Tasks | `ralphe list` | Show all tasks | List |
| Switch Task | `ralphe switch` | Change focus | Updated Context |
| Archive Task | `ralphe archive` | Complete task | Archived Task |
| Show Status | `ralphe status` | Dashboard | Dashboard View |

---

## Capability Matrix by Phase

| Phase | BMAD | GSD | Ralphe | Obsidient |
|-------|------|-----|--------|-----------|
| Analysis | ✅✅✅ | ❌ | ❌ | ✅ |
| Planning | ✅✅✅ | ❌ | ❌ | ✅ |
| Solutioning | ✅✅✅ | ⚠️ | ⚠️ | ✅ |
| Implementation | ⚠️ | ✅✅ | ✅✅✅ | ✅ |
| Maintenance | ❌ | ✅✅✅ | ✅✅ | ✅ |
| Emergency | ❌ | ✅✅✅ | ⚠️ | ✅ |

**Legend:**
- ✅✅✅ Primary
- ✅✅ Strong
- ✅ Capable
- ⚠️ Limited
- ❌ Not suitable

---

## Cross-Capability Workflows

### New Feature Workflow
1. **BMAD** `plan init` → Task created
2. **BMAD** `plan research` → Domain research
3. **BMAD** `design ux` → UX design
4. **BMAD** `design arch` → Architecture
5. **BMAD** `design stories` → Stories created
6. **Ralphe** `run` → Implementation
7. **QA** `audit` → Quality check
8. **Obsidient** `archive` → Task complete

### Bug Fix Workflow
1. **Obsidient** `switch` → Select task
2. **GSD** `run --gsd` → Quick fix
3. **QA** `audit` → Verify fix
4. **Obsidient** `archive` → Complete

### Refactoring Workflow
1. **BMAD** `design arch` → New architecture
2. **Ralphe** `run` → Implement changes
3. **QA** `audit --performance` → Check performance
4. **Obsidient** Archive old patterns

---

## Capability Dependencies

```
BMAD (Analysis)
  ↓
BMAD (Planning)
  ↓
BMAD (Solutioning)
  ↓
[Obsidient: Sync context]
  ↓
Ralphe/GSD (Implementation)
  ↓
[Obsidient: Sync progress]
  ↓
QA (Audit)
  ↓
[Obsidient: Archive]
```

---

## Last Updated

- **Registry**: 2026-04-04T00:00:00Z
- **Version**: 1.0.0
