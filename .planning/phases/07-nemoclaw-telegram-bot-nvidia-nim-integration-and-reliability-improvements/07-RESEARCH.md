# Phase 7: NemoClaw Telegram Bot NVIDIA NIM Integration and Reliability Improvements — Research

**Researched:** 2026-03-20
**Domain:** Node.js Telegram bridge, NVIDIA NIM API, openclaw configuration, systemd user services
**Confidence:** MEDIUM (core stack verified via official sources; some openclaw internals from community gists)

---

## Summary

This phase fixes a deployed NemoClaw Telegram bot (`@AdelClaw_Nemobot`) on VPS 72.60.190.192. Three distinct problems exist: (1) a wrong model ID in `openclaw.json` causing 404s from NVIDIA NIM, (2) synchronous `openclaw agent` invocation in the Telegram bridge causing the "typing" indicator to hang, and (3) an incorrectly-typed systemd user service that does not survive reboots.

The NVIDIA NIM API is fully OpenAI-compatible at `https://integrate.api.nvidia.com/v1`. The confirmed working model is `meta/llama-3.3-70b-instruct`. The `openclaw.json` provider block uses `"api": "openai-completions"`, `"baseUrl": "https://integrate.api.nvidia.com/v1"`, and the auth profile uses `"type": "api_key"` with field `"key"` (not `"token"` or `"apiKey"`). The bridge must use `child_process.spawn` with a Promise wrapper, a per-4-second `setInterval` for typing keep-alive, and exponential backoff retries for 429/5xx errors. The systemd service must be `Type=simple` (not `Type=forking`) with `loginctl enable-linger deploy` so it survives reboot without an active SSH session.

**Primary recommendation:** Fix openclaw.json model + auth-profiles.json first (lowest risk, immediate unblock), then patch the bridge for async+typing-keepalive, then fix the systemd unit, then add retry logic.

---

## Standard Stack

### Core (already installed on VPS)

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| openclaw | 2026.3.11 | Agent CLI and gateway | Installed globally, central tool |
| node-telegram-bot-api | latest npm | Telegram Bot API wrapper | Already used in bridge |
| Node.js | 18.x (VPS system) | Bridge runtime | Already present |
| NVIDIA NIM API | — | LLM inference cloud | Confirmed working, free tier |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `child_process` (stdlib) | Node built-in | Spawn `openclaw agent` as subprocess | Non-blocking async invocation |
| `util.promisify` (stdlib) | Node built-in | Wrap exec/spawn as Promise | Clean async/await pattern |
| systemd user services | — | Process supervision | Reboot-persistent service |
| cloudflared | latest | Expose local gateway externally | Already running via trycloudflare |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Quick Tunnel (trycloudflare) | Named Cloudflare Tunnel | Named tunnel gives stable URL across restarts; quick tunnel changes URL every time — risk: Telegram webhook URL breaks. Consider migrating if reliability is required. |
| `openclaw agent` subprocess | openclaw native Telegram channel | Native channel eliminates the bridge entirely but requires reconfiguring the gateway and removing the custom bridge script |
| `Type=forking` systemd | `Type=simple` | `Type=simple` is correct for processes that stay in foreground; `Type=forking` is only correct when ExecStart forks to background and parent exits |

**Installation (nothing new — all tools present):**
```bash
# Verify openclaw is present
openclaw --version

# Verify node-telegram-bot-api in bridge
node -e "require('node-telegram-bot-api')"
```

---

## Architecture Patterns

### Recommended Project Structure (on VPS, deploy user home)

```
~/.nemoclaw/
├── telegram-bridge-local.js   # patched bridge (fix async here)
├── start-services-local.sh    # service startup
├── start.sh                   # wrapper loading credentials

~/.openclaw/
├── openclaw.json              # model + provider + gateway config (fix model here)
└── agents/main/agent/
    └── auth-profiles.json     # NVIDIA API key (fix field name here)

~/.config/systemd/user/
└── nemoclaw.service           # systemd unit (fix Type here)

~/.nemoclaw/
└── credentials.json           # NVIDIA_API_KEY + TELEGRAM_BOT_TOKEN (secrets, not in git)
```

### Pattern 1: Correct openclaw.json for NVIDIA NIM

**What:** Provider block pointing to NVIDIA's OpenAI-compatible endpoint with correct model ID
**When to use:** Any openclaw installation targeting NVIDIA NIM cloud inference

```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "nvidia": {
        "baseUrl": "https://integrate.api.nvidia.com/v1",
        "api": "openai-completions",
        "models": [
          {
            "id": "meta/llama-3.3-70b-instruct",
            "contextWindow": 131072,
            "maxTokens": 4096,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "nvidia/meta/llama-3.3-70b-instruct"
      }
    }
  }
}
```

Source: [docs.openclaw.ai/providers/nvidia](https://docs.openclaw.ai/providers/nvidia), [gist haltakov](https://gist.github.com/haltakov/72f732bacb7c81a056fc1853cc6e970a)

### Pattern 2: Correct auth-profiles.json Field Names

**What:** The `key` field (not `token` or `apiKey`) is required for `api_key` type profiles in openclaw 2026.x
**When to use:** Any NVIDIA NIM auth profile in openclaw

```json
{
  "version": 1,
  "profiles": {
    "nvidia:manual": {
      "type": "api_key",
      "provider": "nvidia",
      "key": "nvapi-YOUR-KEY-HERE"
    }
  },
  "lastGood": {
    "nvidia": "nvidia:manual"
  }
}
```

Source: [openclaw issue #21448](https://github.com/openclaw/openclaw/issues/21448), [openclaw issue #26916](https://github.com/openclaw/openclaw/issues/26916)

**CRITICAL FIELD NAME:** `"key"` not `"token"` and not `"apiKey"`. This changed between versions. Both field names appear in community examples — use `"key"` for openclaw >= 2026.2.19.

### Pattern 3: Async Non-Blocking Bridge with Typing Keep-Alive

**What:** Use `child_process.spawn` wrapped in a Promise; send `sendChatAction('typing')` every 4 seconds until the subprocess completes
**When to use:** Any Telegram bridge that calls a CLI tool with >5 second execution time

```javascript
// Source: Node.js docs (child_process) + Telegram Bot API (sendChatAction 5s TTL)
const { spawn } = require('child_process');

function runOpenclawAgent(message) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    const errChunks = [];
    // Use spawn, not exec — avoids 200KB buffer limit
    const proc = spawn('openclaw', ['agent', '--message', message], {
      env: { ...process.env },
      timeout: 120000  // 2-minute hard limit
    });
    proc.stdout.on('data', chunk => chunks.push(chunk));
    proc.stderr.on('data', chunk => errChunks.push(chunk));
    proc.on('close', code => {
      if (code === 0) {
        resolve(Buffer.concat(chunks).toString('utf8').trim());
      } else {
        reject(new Error(`openclaw exited ${code}: ${Buffer.concat(errChunks)}`));
      }
    });
    proc.on('error', reject);
  });
}

async function handleMessage(bot, msg) {
  const chatId = msg.chat.id;
  // Start typing keep-alive BEFORE spawning subprocess
  const typingInterval = setInterval(() => {
    bot.sendChatAction(chatId, 'typing').catch(() => {}); // swallow errors
  }, 4000);
  bot.sendChatAction(chatId, 'typing').catch(() => {});

  try {
    const response = await runOpenclawAgent(msg.text);
    await bot.sendMessage(chatId, response);
  } catch (err) {
    await bot.sendMessage(chatId, formatError(err));
  } finally {
    clearInterval(typingInterval);  // MUST clear — bug if omitted
  }
}
```

Source: [Node.js child_process docs](https://nodejs.org/api/child_process.html), [Telegram Bot API sendChatAction](https://core.telegram.org/bots/api), [openclaw issue #26586](https://github.com/openclaw/openclaw/issues/26586)

### Pattern 4: Exponential Backoff Retry for NVIDIA NIM Errors

**What:** Retry 429 and 5xx responses with exponential backoff + jitter; do not retry 404/400/401
**When to use:** Any HTTP call to NVIDIA NIM API

```javascript
async function withRetry(fn, maxAttempts = 3, baseDelayMs = 1000) {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      const isRetryable = err.statusCode === 429
        || err.statusCode === 500
        || err.statusCode === 503;
      if (!isRetryable || attempt === maxAttempts) throw err;
      const jitter = Math.random() * 500;
      const delay = baseDelayMs * Math.pow(2, attempt - 1) + jitter;
      await new Promise(r => setTimeout(r, delay));
    }
  }
}
```

Source: [NVIDIA developer forums (429 thread)](https://forums.developer.nvidia.com/t/getting-429-too-many-request-for-nim-cloud-api/335755), standard exponential backoff pattern

### Pattern 5: Correct systemd User Service (Type=simple)

**What:** `Type=simple` is correct for `start.sh` that runs in foreground; `Type=forking` would require the main process to fork and the parent to exit
**When to use:** Any long-running Node.js/shell process managed as a systemd user service

```ini
[Unit]
Description=NemoClaw Telegram Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash /home/deploy/.nemoclaw/start.sh
Restart=always
RestartSec=10
Environment=HOME=/home/deploy
Environment=PATH=/usr/local/bin:/usr/bin:/bin:/home/deploy/.npm-global/bin

[Install]
WantedBy=default.target
```

After deploying, enable lingering so the service survives SSH disconnects and reboots:
```bash
loginctl enable-linger deploy
systemctl --user daemon-reload
systemctl --user enable nemoclaw.service
systemctl --user start nemoclaw.service
```

Source: [systemd.service manpage](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html), [ArchWiki systemd/User](https://wiki.archlinux.org/title/Systemd/User), [systemd --user lingering guide](https://blog.shukebeta.com/2024/10/24/how-to-enable-user-level-systemd-services-to-start-automatically-on-ubuntu-after-reboot/)

### Anti-Patterns to Avoid

- **`Type=forking` for a shell wrapper that calls `node`:** The shell is the parent; once it execs node, node becomes the process. systemd will think service started when shell exits, then kill the child. Use `Type=simple`.
- **`exec` instead of `spawn` for openclaw:** `child_process.exec` buffers all output in memory with a 200KB default limit. `openclaw agent` output can exceed this. Use `spawn` with streaming.
- **Not clearing `setInterval` for typing keep-alive:** Known bug in openclaw bridge implementations (issue #26586). Always `clearInterval` in a `finally` block.
- **Using `Type=forking` with `PIDFile=` pointing to a shell PID:** The PID of the shell is not the PID of the node process; systemd will track the wrong process.
- **Quick Tunnel (trycloudflare) for webhook delivery:** URL changes on every restart. If using Telegram webhook mode (not polling), the bot will stop receiving messages after a service restart. Currently the bridge uses long-polling, so this is acceptable for now, but note the fragility.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Typing keep-alive loop | Custom timing logic | `setInterval` at 4000ms with `clearInterval` in finally | Telegram's 5s TTL requires periodic renewal; 4s is safe margin |
| Retry with backoff | Custom retry loop from scratch | Standard exponential backoff pattern (shown above) | Need jitter to avoid thundering herd; 3 retries is sufficient for NIM free tier |
| Process supervision | Custom restart script with `while true; do ... done` | systemd `Restart=always` + `RestartSec=10` | systemd handles SIGTERM, log capture, start order, and boot-time auto-start |
| Auth key loading | Inline API key in code | `credentials.json` loaded at start, set as env var | Secrets must not appear in process args (visible in `ps aux`) |

**Key insight:** The bridge's current synchronous blocking design is the highest-impact problem. Every second the agent blocks is a second the event loop cannot process new Telegram updates — meaning concurrent messages queue up silently and may time out.

---

## Common Pitfalls

### Pitfall 1: Wrong auth-profiles.json Field Name

**What goes wrong:** openclaw silently fails to authenticate with NVIDIA NIM; requests go out without the API key; all calls return 401 or 403
**Why it happens:** openclaw changed `"token"` to `"key"` in version 2026.2.19; community gists and docs show both field names depending on their age
**How to avoid:** Always use `"type": "api_key"` + `"key": "nvapi-..."` in the profile block
**Warning signs:** openclaw logs show `Authentication failed` or `401 Unauthorized` from `integrate.api.nvidia.com`

### Pitfall 2: Model ID 404 From NVIDIA NIM

**What goes wrong:** HTTP 404 from `integrate.api.nvidia.com/v1/chat/completions`; openclaw reports model not found
**Why it happens:** `nvidia/nemotron-3-super-120b-a12b` does not exist on the public NIM API; only specific model IDs are available
**How to avoid:** Use confirmed working model string `meta/llama-3.3-70b-instruct`; test with `curl` before deploying
**Warning signs:** HTTP 404 in bridge stderr; openclaw output contains "model not found"

Confirmed working models on `integrate.api.nvidia.com/v1` (as of 2026-03-20):
- `meta/llama-3.3-70b-instruct` (confirmed in phase description)
- `meta/llama-3.1-70b-instruct`
- `meta/llama-4-maverick-17b-128e-instruct`
- `meta/llama-4-scout-17b-16e-instruct`
- `mistralai/mistral-nemotron`

### Pitfall 3: setInterval Not Cleared After Agent Response

**What goes wrong:** Bot keeps sending "typing..." indicator forever after it sends the response; Telegram may throttle the bot
**Why it happens:** Forgetting `clearInterval` when the subprocess rejects with an error (only clearing on success path)
**How to avoid:** Always `clearInterval(typingInterval)` in the `finally` block of a try/catch/finally
**Warning signs:** `@AdelClaw_Nemobot` shows "typing..." permanently in the chat even after message is delivered

### Pitfall 4: Type=forking With a Shell Wrapper

**What goes wrong:** systemd marks service as "active" immediately when shell forks (which it never does), or kills the process when the shell exits
**Why it happens:** `start.sh` runs in foreground and executes node; the shell does NOT fork; systemd misinterprets the lifecycle
**How to avoid:** Use `Type=simple`; systemd tracks the direct ExecStart process
**Warning signs:** `systemctl --user status nemoclaw` shows "activating" then "dead" immediately after reboot

### Pitfall 5: Missing loginctl enable-linger

**What goes wrong:** systemd user services are destroyed when the last user session ends (SSH disconnect)
**Why it happens:** Without lingering, user slice is torn down on logout
**How to avoid:** Run `loginctl enable-linger deploy` once on the VPS
**Warning signs:** Bot works while SSH is connected but dies when you disconnect

### Pitfall 6: NVIDIA NIM Free Tier Rate Limits (40 RPM)

**What goes wrong:** 429 responses from NVIDIA NIM during rapid testing or if multiple users message simultaneously
**Why it happens:** Free tier limit is 40 requests per minute; the bot + agent call = 1 NIM request per user message
**How to avoid:** Implement retry with exponential backoff (shown above); inform users of "thinking" delay via typing indicator; do not retry in burst
**Warning signs:** HTTP 429 in openclaw stderr; users get error messages during busy periods

### Pitfall 7: API Key Exposed in Process Arguments

**What goes wrong:** `NVIDIA_API_KEY` visible in `ps aux` output; security risk
**Why it happens:** Some bridge implementations pass the key as a CLI argument
**How to avoid:** Load credentials from `~/.nemoclaw/credentials.json` and export as environment variable before calling openclaw; the key should be in the environment, not in `argv`
**Warning signs:** Running `ps aux | grep openclaw` shows the key value

---

## Code Examples

### Test NVIDIA NIM Model Directly

```bash
# Source: NVIDIA NIM API (OpenAI-compatible), test before touching openclaw config
curl https://integrate.api.nvidia.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $NVIDIA_API_KEY" \
  -d '{
    "model": "meta/llama-3.3-70b-instruct",
    "messages": [{"role": "user", "content": "Hello, respond in one sentence."}],
    "max_tokens": 50
  }'
# Expected: HTTP 200 with {"choices":[{"message":{"content":"..."}}]}
# 404 = wrong model ID, 401 = bad API key, 429 = rate limited
```

### Error Classifier for Bridge

```javascript
// Source: NVIDIA developer forums + Telegram Bot API docs
function classifyError(err) {
  if (err.statusCode === 404 || (err.message && err.message.includes('model not found'))) {
    return 'Sorry, the AI model is misconfigured. Contact admin.';
  }
  if (err.statusCode === 429) {
    return 'The AI service is busy right now. Please try again in a minute.';
  }
  if (err.statusCode >= 500) {
    return 'The AI service is temporarily unavailable. Please try again shortly.';
  }
  if (err.code === 'ETIMEDOUT' || err.message.includes('timeout')) {
    return 'The AI took too long to respond. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}
```

### Verify systemd Service After Fix

```bash
# Run on VPS as deploy user
loginctl enable-linger deploy
systemctl --user daemon-reload
systemctl --user restart nemoclaw.service
systemctl --user status nemoclaw.service
# Expected: "active (running)" with PID shown

# Simulate reboot without rebooting (test lingering)
systemctl --user stop nemoclaw.service
sleep 2
systemctl --user start nemoclaw.service
journalctl --user -u nemoclaw.service -n 20
```

### Check openclaw Gateway Status

```bash
# Run on VPS as deploy user
openclaw gateway status
# If dead: openclaw gateway start
# Check model config is valid:
openclaw config get agents.defaults.model
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `nvidia/nemotron-3-super-120b-a12b` | `meta/llama-3.3-70b-instruct` | 2026-03 (model removed) | All NIM calls were 404ing |
| `auth-profiles.json` field `"token"` | Field `"key"` | openclaw 2026.2.19 | Auth silently fails with old field |
| `Type=forking` systemd | `Type=simple` | Always (mismatch was introduced) | Service dies on reboot |
| Sync `openclaw agent` call | Async spawn + typing keep-alive | This phase | Bot becomes responsive; no blocking |

**Deprecated/outdated:**
- `nvidia/nemotron-3-super-120b-a12b`: Model ID removed from NVIDIA NIM public API — use `meta/llama-3.3-70b-instruct`
- `"token"` field in auth-profiles.json: Replaced by `"key"` in openclaw >= 2026.2.19
- `child_process.exec` for long-running subprocesses: Use `spawn` to avoid 200KB buffer limit

---

## Open Questions

1. **Is the bridge currently using Telegram long-polling or webhook mode?**
   - What we know: Bridge file is `telegram-bridge-local.js`; cloudflared is running (suggesting webhook was intended or tried)
   - What's unclear: Whether `TelegramBot` is initialized with `{polling: true}` or webhook config
   - Recommendation: Inspect bridge file on VPS before writing the patch; polling is safer on a 2-CPU VPS

2. **Does openclaw gateway need to be running alongside the bridge, or does the bridge call `openclaw agent` standalone?**
   - What we know: Phase description says bridge runs `openclaw agent` synchronously; gateway may or may not be needed
   - What's unclear: Whether `openclaw agent` requires a running gateway or is fully standalone
   - Recommendation: Test `openclaw agent --message "hello"` on VPS without gateway running

3. **Is there a lock/concurrency concern for multiple simultaneous `openclaw agent` spawns?**
   - What we know: VPS has 2 CPUs; openclaw agent is heavyweight; NVIDIA NIM has 40 RPM limit
   - What's unclear: Whether openclaw agent uses a lock file that prevents parallel runs
   - Recommendation: Implement a simple in-memory queue (Map of chatId → Promise) to serialize requests per user

4. **Quick Tunnel URL stability**
   - What we know: cloudflared with trycloudflare generates a new random URL on every restart; current bot likely uses polling (not webhooks) since the URL instability would break webhooks
   - What's unclear: Whether the Telegram bot token is set for webhook or polling mode
   - Recommendation: Confirm polling mode; if webhook, migrate to named Cloudflare Tunnel

---

## Validation Architecture

`nyquist_validation` is enabled in `.planning/config.json`.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Manual smoke tests via SSH (no automated test framework — this is a live VPS-only component) |
| Config file | None — scripts are ad-hoc bash on the VPS |
| Quick run command | `ssh deploy@72.60.190.192 "systemctl --user status nemoclaw"` |
| Full suite command | See Phase Requirements smoke test map below |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NIM-01 | NVIDIA NIM returns 200 for `meta/llama-3.3-70b-instruct` | smoke | `curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $NVIDIA_API_KEY" -H "Content-Type: application/json" -d '{"model":"meta/llama-3.3-70b-instruct","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' https://integrate.api.nvidia.com/v1/chat/completions` | ❌ Wave 0 |
| NIM-02 | openclaw agent responds to a test message end-to-end | smoke | `ssh deploy@72.60.190.192 "openclaw agent --message 'ping' 2>&1"` | ❌ Wave 0 |
| BOT-01 | Telegram bot responds in chat (async, no hang) | manual | Send `/start` to `@AdelClaw_Nemobot` and verify response within 30s | N/A (manual) |
| BOT-02 | Typing indicator appears and clears correctly | manual | Send message, verify "typing..." shows and disappears after response | N/A (manual) |
| BOT-03 | Error message is user-friendly on 429 | smoke | Trigger 40+ requests in 60s (or mock), verify friendly message | ❌ Wave 0 |
| SVC-01 | systemd service restarts automatically after kill | smoke | `ssh deploy@72.60.190.192 "kill \$(systemctl --user show nemoclaw -p MainPID --value) && sleep 12 && systemctl --user is-active nemoclaw"` | ❌ Wave 0 |
| SVC-02 | Service active after session disconnect (lingering) | smoke | Manual: disconnect SSH, reconnect, check `systemctl --user status nemoclaw` | N/A (manual) |

### Sampling Rate

- **Per task commit:** `ssh deploy@72.60.190.192 "systemctl --user status nemoclaw && openclaw gateway status"`
- **Per wave merge:** Full smoke map above (NIM-01, NIM-02, SVC-01)
- **Phase gate:** BOT-01 and BOT-02 (manual Telegram test) green before verification

### Wave 0 Gaps

- [ ] `~/.nemoclaw/smoke-test.sh` — covers NIM-01, NIM-02, SVC-01 (create in Wave 0)
- [ ] No automated test framework exists; all tests are SSH + manual Telegram interaction

---

## Sources

### Primary (HIGH confidence)

- [docs.openclaw.ai/providers/nvidia](https://docs.openclaw.ai/providers/nvidia) — provider config format, baseUrl, api field
- [docs.openclaw.ai/channels/telegram](https://docs.openclaw.ai/channels/telegram) — native Telegram channel config
- [docs.openclaw.ai/platforms/linux](https://docs.openclaw.ai/platforms/linux) — systemd service setup, Type=simple, `openclaw gateway install`
- [nodejs.org/api/child_process.html](https://nodejs.org/api/child_process.html) — spawn vs exec, timeout, promise wrapping
- [core.telegram.org/bots/api](https://core.telegram.org/bots/api) — sendChatAction 5-second TTL
- [systemd.service manpage](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) — Type=simple vs Type=forking
- [docs.nvidia.com/nim/reference/meta-llama-3_3-70b-instruct](https://docs.api.nvidia.com/nim/reference/meta-llama-3_3-70b-instruct) — model ID confirmed

### Secondary (MEDIUM confidence)

- [gist haltakov openclaw.json](https://gist.github.com/haltakov/72f732bacb7c81a056fc1853cc6e970a) — full config example verified against official docs
- [openclaw issue #21448](https://github.com/openclaw/openclaw/issues/21448) — `"key"` not `"token"` for api_key profiles (breaking change 2026.2.19)
- [openclaw issue #26916](https://github.com/openclaw/openclaw/issues/26916) — auth field name confusion documented
- [openclaw issue #26586](https://github.com/openclaw/openclaw/issues/26586) — typing keepalive interval not cleared bug
- [moltfounders.com openclaw config reference](https://moltfounders.com/openclaw-runbook/config-reference) — gateway, models.mode: merge pattern
- [ArchWiki systemd/User](https://wiki.archlinux.org/title/Systemd/User) — WantedBy=default.target, loginctl enable-linger

### Tertiary (LOW confidence — needs validation)

- [NVIDIA developer forums — 429 rate limiting](https://forums.developer.nvidia.com/t/getting-429-too-many-request-for-nim-cloud-api/335755) — "40 RPM" limit sourced from community research, not official NVIDIA docs; verify against current limits
- [Cloudflare trycloudflare docs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/) — quick tunnel URL instability (check if polling vs webhook mode matters)

---

## Metadata

**Confidence breakdown:**

- openclaw.json config format: MEDIUM — official docs + gist cross-verified; auth field name has conflicting community info, but GitHub issues confirm `"key"` is correct for >= 2026.2.19
- NVIDIA NIM model IDs: HIGH — confirmed working model from phase description + official NVIDIA NIM catalog
- systemd Type=simple vs forking: HIGH — official systemd.service manpage
- Async bridge pattern: HIGH — Node.js stdlib documentation
- Typing keep-alive pattern: MEDIUM — Telegram official docs (5s TTL) + openclaw bug report confirming clearInterval requirement
- NVIDIA NIM rate limits: LOW — community-sourced "40 RPM"; no official documentation found

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable platform; openclaw config schema could shift with minor releases)
