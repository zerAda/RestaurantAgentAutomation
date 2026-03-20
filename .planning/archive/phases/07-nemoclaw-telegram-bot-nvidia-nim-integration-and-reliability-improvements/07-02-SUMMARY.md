---
phase: 07-nemoclaw-telegram-bot-nvidia-nim-integration-and-reliability-improvements
plan: "02"
subsystem: nemoclaw-telegram-bridge
tags: [telegram, bridge, async, retry, node.js, vps]
dependency_graph:
  requires: []
  provides: [BOT-01, BOT-02, BOT-03]
  affects: [nemoclaw-telegram-bridge, @AdelClaw_Nemobot]
tech_stack:
  added: []
  patterns: [async-spawn-promise, exponential-backoff-retry, typing-keepalive-setinterval]
key_files:
  created:
    - tools/telegram-bridge-local-patched.js
  modified:
    - "~/.nemoclaw/telegram-bridge-local.js (on VPS, 246 -> 277 lines)"
decisions:
  - "Preserve existing polling architecture and credential loading; only replace message handling core"
  - "Use ES5-compatible var in withRetry/classifyError for maximum Node.js compatibility"
  - "clearInterval moved to finally block from try block to prevent typing leak on errors"
  - "runAgentInSandbox kept intact; only wired through withRetry at call site"
metrics:
  duration: "7 minutes"
  completed: "2026-03-20T20:00:50Z"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 1
---

# Phase 07 Plan 02: Async Telegram Bridge with Typing Keepalive, Retry, and Error Classification Summary

**One-liner:** Non-blocking async Telegram bridge with 4-second typing keepalive, 3-attempt exponential backoff retry for 429/5xx, and user-friendly error classification deployed to VPS @AdelClaw_Nemobot.

## What Was Built

Patched `~/.nemoclaw/telegram-bridge-local.js` on VPS (72.60.190.192) to replace synchronous blocking behavior with an async, resilient, user-friendly message handler.

**Changes made to the bridge:**
1. Removed `execSync` from the `require('child_process')` destructure (was imported but unused after prior refactor)
2. Added `withRetry(fn, maxAttempts=3, baseDelayMs=1000)` — exponential backoff with jitter for retryable errors (429, 500, 503, ETIMEDOUT)
3. Added `classifyError(err)` — maps error codes/message patterns to user-readable strings (404/model-not-found, 429, 5xx, timeout, fallback)
4. Moved `clearInterval(typingInterval)` from the `try` block to a `finally` block — prevents the typing indicator from leaking when `runAgentInSandbox` rejects
5. Wrapped `runAgentInSandbox` call with `withRetry(...)` in the poll handler
6. Replaced raw `Error: ${err.message}` error send with `classifyError(err)` for user-friendly output
7. Updated startup banner to show correct model name `meta/llama-3.3-70b-instruct` and "Async bridge" label

## Tasks Completed

| Task | Name | Status | Commit | Key Output |
|------|------|--------|--------|------------|
| 1 | Patch telegram-bridge-local.js with async spawn, typing keepalive, retries, and error handling | DONE | 8debf95 | tools/telegram-bridge-local-patched.js + VPS deploy |
| 2 | Restart bridge process and verify it runs without errors | DONE | bf93d73 | PID 3325183 running, banner shows patched version |

## Verification Results

All acceptance criteria confirmed:

| Check | Result |
|-------|--------|
| `node --check` exits 0 (valid JS syntax) | PASS |
| `grep spawn` matches | PASS (3 occurrences) |
| `grep setInterval` matches | PASS (line 227) |
| `grep clearInterval` in finally block | PASS (line 241, inside finally) |
| `grep withRetry` matches | PASS (2 occurrences: definition + call site) |
| `grep classifyError` matches | PASS (2 occurrences: definition + error handler) |
| `grep execSync` returns 0 | PASS (no synchronous calls) |
| `grep 4000` matches (4s typing interval) | PASS (3 occurrences) |
| `grep 120000` matches (subprocess timeout) | PASS |
| `.bak` backup exists | PASS (`telegram-bridge-local.js.bak` 8434 bytes) |
| Bridge process running | PASS (PID 3325183, `ps aux` confirmed) |
| No SyntaxError or crash in log | PASS (clean startup banner in bridge log) |
| Bot connected to Telegram | PASS (@AdelClaw_Nemobot shown in banner) |

## Requirements Met

- BOT-01: Telegram bridge handles messages asynchronously without blocking the event loop (spawn-based, not sync)
- BOT-02: Typing indicator appears (setInterval at 4000ms) and clears after response (clearInterval in finally)
- BOT-03: Rate-limited or server-error responses produce user-friendly messages via classifyError()

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] clearInterval was inside try block instead of finally**
- **Found during:** Task 1 — reading the original bridge showed `clearInterval` inside the `try` success path and `catch` error path separately
- **Issue:** If an exception was thrown between the two clearInterval calls, the interval would leak
- **Fix:** Moved single `clearInterval(typingInterval)` to `finally` block as specified in the plan patterns
- **Files modified:** `tools/telegram-bridge-local-patched.js`
- **Commit:** 8debf95

**2. [Rule 3 - Blocking Issue] CRLF line endings from Windows Write tool caused node --check to fail**
- **Found during:** Task 1 verification step
- **Issue:** File deployed via scp had CRLF line terminators; `node --check` returned SYNTAX ERROR
- **Fix:** `sed -i 's/\r//' ~/.nemoclaw/telegram-bridge-local.js` on VPS to convert to LF
- **Files modified:** `~/.nemoclaw/telegram-bridge-local.js` (VPS only)
- **Commit:** 8debf95 (included in same task commit)

**3. [Rule 3 - Blocking Issue] Node not in default SSH PATH — used NVM sourcing for validation**
- **Found during:** Task 1 verification — `node --check` returned "command not found"
- **Issue:** Node installed via NVM at `/home/deploy/.nvm/versions/node/v22.22.1/bin/node`; not in default SSH PATH
- **Fix:** Used `bash -l -c` (login shell) for all subsequent SSH commands which sources NVM
- **Files modified:** None (runtime workaround)

## Self-Check: PASSED

Files checked:
- `tools/telegram-bridge-local-patched.js` — FOUND (277 lines, local copy)
- `~/.nemoclaw/telegram-bridge-local.js` — FOUND on VPS (277 lines, syntax OK)
- `~/.nemoclaw/telegram-bridge-local.js.bak` — FOUND on VPS (backup 8434 bytes)

Commits checked:
- `8debf95` — feat(07-02): patch telegram-bridge — FOUND
- `bf93d73` — chore(07-02): restart telegram bridge — FOUND

Bridge process: PID 3325183 running on VPS, banner confirms patched version.
