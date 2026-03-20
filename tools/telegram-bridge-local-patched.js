#!/usr/bin/env node
// SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

/**
 * Telegram -> NemoClaw bridge.
 *
 * Messages from Telegram are forwarded to the OpenClaw agent running
 * inside the sandbox. When the agent needs external access, the
 * OpenShell TUI lights up for approval. Responses go back to Telegram.
 *
 * Env:
 *   TELEGRAM_BOT_TOKEN  -- from @BotFather
 *   NVIDIA_API_KEY      -- for inference
 *   SANDBOX_NAME        -- sandbox name (default: nemoclaw)
 *   ALLOWED_CHAT_IDS    -- comma-separated Telegram chat IDs to accept (optional, accepts all if unset)
 */

const https = require("https");
const { spawn } = require("child_process");
// openshell removed -- local mode

const TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const API_KEY = process.env.NVIDIA_API_KEY;
const SANDBOX = process.env.SANDBOX_NAME || "nemoclaw";
const ALLOWED_CHATS = process.env.ALLOWED_CHAT_IDS
  ? process.env.ALLOWED_CHAT_IDS.split(",").map((s) => s.trim())
  : null;

if (!TOKEN) { console.error("TELEGRAM_BOT_TOKEN required"); process.exit(1); }
if (!API_KEY) { console.error("NVIDIA_API_KEY required"); process.exit(1); }

let offset = 0;
const activeSessions = new Map(); // chatId -> message history

// ++ Retry helper (exponential backoff, 3 attempts) ++++++++++++++++

async function withRetry(fn, maxAttempts, baseDelayMs) {
  maxAttempts = maxAttempts || 3;
  baseDelayMs = baseDelayMs || 1000;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      var msg = err.message || "";
      var isRetryable = msg.includes("429") || msg.includes("500") ||
        msg.includes("503") || msg.includes("ETIMEDOUT");
      if (!isRetryable || attempt === maxAttempts) throw err;
      var jitter = Math.random() * 500;
      var delay = baseDelayMs * Math.pow(2, attempt - 1) + jitter;
      console.log("Retry " + attempt + "/" + maxAttempts + " after " + Math.round(delay) + "ms...");
      await new Promise(function(r) { setTimeout(r, delay); });
    }
  }
}

// ++ Error classifier (user-friendly messages) +++++++++++++++++++++

function classifyError(err) {
  var msg = err.message || "";
  if (msg.includes("404") || msg.includes("model not found")) {
    return "Sorry, the AI model is misconfigured. Contact admin.";
  }
  if (msg.includes("429")) {
    return "The AI service is busy right now. Please try again in a minute.";
  }
  if (msg.includes("500") || msg.includes("503")) {
    return "The AI service is temporarily unavailable. Please try again shortly.";
  }
  if (msg.includes("timeout") || msg.includes("ETIMEDOUT")) {
    return "The AI took too long to respond. Please try again.";
  }
  return "Something went wrong. Please try again.";
}

// -- Telegram API helpers ------------------------------------------

function tgApi(method, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = https.request(
      {
        hostname: "api.telegram.org",
        path: `/bot${TOKEN}/${method}`,
        method: "POST",
        headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data) },
      },
      (res) => {
        let buf = "";
        res.on("data", (c) => (buf += c));
        res.on("end", () => {
          try { resolve(JSON.parse(buf)); } catch { resolve({ ok: false, error: buf }); }
        });
      },
    );
    req.on("error", reject);
    req.write(data);
    req.end();
  });
}

async function sendMessage(chatId, text, replyTo) {
  // Telegram max message length is 4096
  const chunks = [];
  for (let i = 0; i < text.length; i += 4000) {
    chunks.push(text.slice(i, i + 4000));
  }
  for (const chunk of chunks) {
    await tgApi("sendMessage", {
      chat_id: chatId,
      text: chunk,
      reply_to_message_id: replyTo,
      parse_mode: "Markdown",
    }).catch(() =>
      // Retry without markdown if it fails (unbalanced formatting)
      tgApi("sendMessage", { chat_id: chatId, text: chunk, reply_to_message_id: replyTo }),
    );
  }
}

async function sendTyping(chatId) {
  await tgApi("sendChatAction", { chat_id: chatId, action: "typing" }).catch(() => {});
}

// -- Run agent inside sandbox -------------------------------------

function runAgentInSandbox(message, sessionId) {
  return new Promise((resolve, reject) => {
    // Local mode -- run openclaw directly without Brev VM
    const escaped = message.replace(/'/g, "'\\'' ");
    const cmd = `openclaw agent --agent main --local -m '${escaped}' --session-id 'tg-${sessionId}'`;

    const proc = spawn("bash", ["-c", cmd], {
      timeout: 120000,
      stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env, NVIDIA_API_KEY: API_KEY },
    });

    let stdout = "";
    let stderr = "";

    proc.stdout.on("data", (d) => (stdout += d.toString()));
    proc.stderr.on("data", (d) => (stderr += d.toString()));

    proc.on("close", (code) => {
      // Extract the actual agent response -- skip setup lines
      const lines = stdout.split("\n");
      const responseLines = lines.filter(
        (l) =>
          !l.startsWith("Setting up NemoClaw") &&
          !l.startsWith("[plugins]") &&
          !l.startsWith("(node:") &&
          !l.includes("NemoClaw ready") &&
          !l.includes("NemoClaw registered") &&
          !l.includes("openclaw agent") &&
          !l.includes("\u250c\u2500") &&
          !l.includes("\u2502 ") &&
          !l.includes("\u2514\u2500") &&
          l.trim() !== "",
      );

      const response = responseLines.join("\n").trim();

      if (response) {
        resolve(response);
      } else if (code !== 0) {
        reject(new Error("openclaw exited " + code + ": " + stderr.trim().slice(0, 500)));
      } else {
        resolve("(no response)");
      }
    });

    proc.on("error", reject);
  });
}

// -- Poll loop ----------------------------------------------------

async function poll() {
  try {
    const res = await tgApi("getUpdates", { offset, timeout: 30 });

    if (res.ok && res.result && res.result.length > 0) {
      for (const update of res.result) {
        offset = update.update_id + 1;

        const msg = update.message;
        if (!msg || !msg.text) continue;

        const chatId = String(msg.chat.id);

        // Access control
        if (ALLOWED_CHATS && !ALLOWED_CHATS.includes(chatId)) {
          console.log("[ignored] chat " + chatId + " not in allowed list");
          continue;
        }

        const userName = (msg.from && msg.from.first_name) || "someone";
        console.log("[" + chatId + "] " + userName + ": " + msg.text);

        // Handle /start
        if (msg.text === "/start") {
          await sendMessage(
            chatId,
            "NemoClaw -- powered by meta/llama-3.3-70b-instruct\n\n" +
              "Send me a message and I will run it through the OpenClaw agent.\n\n" +
              "Type anything to begin.",
            msg.message_id,
          );
          continue;
        }

        // Handle /reset
        if (msg.text === "/reset") {
          activeSessions.delete(chatId);
          await sendMessage(chatId, "Session reset.", msg.message_id);
          continue;
        }

        // Skip non-text commands
        if (msg.text.startsWith("/")) continue;

        // Send initial typing indicator
        await sendTyping(chatId);

        // Keep a typing indicator going every 4 seconds while agent runs
        const typingInterval = setInterval(() => {
          sendTyping(chatId);
        }, 4000);

        try {
          const response = await withRetry(function() {
            return runAgentInSandbox(msg.text, chatId);
          });
          console.log("[" + chatId + "] agent: " + response.slice(0, 100) + "...");
          await sendMessage(chatId, response || "No response from AI.", msg.message_id);
        } catch (err) {
          console.error("Agent error:", err.message);
          await sendMessage(chatId, classifyError(err), msg.message_id);
        } finally {
          clearInterval(typingInterval);
        }
      }
    }
  } catch (err) {
    console.error("Poll error:", err.message);
  }

  // Continue polling
  setTimeout(poll, 100);
}

// -- Main ---------------------------------------------------------

async function main() {
  const me = await tgApi("getMe", {});
  if (!me.ok) {
    console.error("Failed to connect to Telegram:", JSON.stringify(me));
    process.exit(1);
  }

  console.log("");
  console.log("  +-----------------------------------------------------+");
  console.log("  |  NemoClaw Telegram Bridge                           |");
  console.log("  |                                                     |");
  console.log("  |  Bot:      @" + (me.result.username + "                    ").slice(0, 37) + "|");
  console.log("  |  Sandbox:  " + (SANDBOX + "                              ").slice(0, 40) + "|");
  console.log("  |  Model:    meta/llama-3.3-70b-instruct             |");
  console.log("  |                                                     |");
  console.log("  |  Async bridge: spawn + typing keepalive + retry    |");
  console.log("  +-----------------------------------------------------+");
  console.log("");

  poll();
}

main();
