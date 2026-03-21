# RESTO BOT — Claude Code Pack (Anthropic-style Skills)

This pack is designed to be dropped into the repo root (copy/merge).
It provides:
- A strict operating contract for Claude Code (Staff+ Platform/SRE/Security)
- A skills library in `.claude/skills/*` following Anthropic `skills` conventions
- Runbook templates, release checklists, and verification harness expectations

## Install
1. Copy `CLAUDE.md`, `CLAUDE_OPERATING_CONTRACT.md`, and `.claude/` into your repository root.
2. If you already have these files, merge carefully (prefer stricter rules).
3. In Claude Code, set the project instructions to use `CLAUDE.md`.

## How to use
- Ask Claude: "Start with Repo Map using repo_intelligence, then run threat_modeling_restobot and produce P0 plan."
- Or: "Implement P0 items with minimal diffs, include PATCHLOG + TEST_REPORT updates."
