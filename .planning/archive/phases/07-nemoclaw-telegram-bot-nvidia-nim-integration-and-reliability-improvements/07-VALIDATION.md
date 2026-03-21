---
phase: 7
slug: nemoclaw-telegram-bot-nvidia-nim-integration-and-reliability-improvements
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash / curl (integration smoke tests on VPS) |
| **Config file** | none — tests are SSH commands |
| **Quick run command** | `ssh deploy@72.60.190.192 'cat /tmp/nemoclaw-services-default/telegram-bridge.log | tail -5'` |
| **Full suite command** | `ssh deploy@72.60.190.192 'bash ~/.nemoclaw/start.sh --status'` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick log check
- **After every plan wave:** Run full status + send test Telegram message
- **Before `/gsd:verify-work`:** Bot must respond to "hello" within 15s
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 7-01-01 | 01 | 1 | Model fix | integration | `ssh deploy@72.60.190.192 'cat ~/.openclaw/openclaw.json \| grep llama-3.3'` | ✅ | ⬜ pending |
| 7-01-02 | 01 | 1 | Auth fix | integration | `ssh deploy@72.60.190.192 'cat ~/.openclaw/agents/main/agent/auth-profiles.json \| grep "\"key\""'` | ✅ | ⬜ pending |
| 7-02-01 | 02 | 1 | Async bridge | integration | `ssh deploy@72.60.190.192 'grep -c "setInterval\|clearInterval" ~/.nemoclaw/telegram-bridge-local.js'` | ✅ | ⬜ pending |
| 7-02-02 | 02 | 1 | Error handling | integration | `ssh deploy@72.60.190.192 'grep -c "retry\|backoff\|429" ~/.nemoclaw/telegram-bridge-local.js'` | ✅ | ⬜ pending |
| 7-03-01 | 03 | 2 | systemd Type=simple | integration | `ssh deploy@72.60.190.192 'grep "Type=simple" ~/.config/systemd/user/nemoclaw.service'` | ✅ | ⬜ pending |
| 7-03-02 | 03 | 2 | linger enabled | integration | `ssh deploy@72.60.190.192 'loginctl show-user deploy \| grep -i linger'` | ✅ | ⬜ pending |
| 7-04-01 | 04 | 2 | E2E bot response | manual | Send "hello" to @AdelClaw_Nemobot, get response within 15s | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- Existing VPS infrastructure covers all phase requirements.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Bot responds to Telegram message | E2E NIM inference | Requires Telegram client | Send "hello" to @AdelClaw_Nemobot, expect response within 15s |
| Bot handles multi-message burst | Rate limiting | Requires Telegram client | Send 5 messages in 2s, expect graceful handling |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
