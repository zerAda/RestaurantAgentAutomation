---
description: Handover from Antigravity to Claude Code
---

An implementation plan from Antigravity should be structured to be easily understood and executed by an AI agent (Claude Code).

1. **Context Initialization**:
   Ensure Claude Code has all necessary file context. Use `view_file` on the key files mentioned in the plan.

2. **Execute Steps**:
   Follow the checkboxes in the plan sequentially. Use `multi_replace_file_content` or `write_to_file` as appropriate.

3. **Internal Verification**:
   Use terminal commands to verify the syntax and functionality after each modification.

4. **Status Report & Handback**:
   Update Antigravity when the execution is complete. If an error occurs that Claude cannot solve, pass the error log back to Antigravity for a **Replan**.

5. **Antigravity Audit**:
   Antigravity will perform a final audit. If anything is missing or broken, the loop restarts at Step 1.

> [!TIP]
> **Piping to Claude**: You can pipe my instructions directly if using the Claude CLI:
> `cat .gemini/antigravity/brain/handoff.md | claude`
