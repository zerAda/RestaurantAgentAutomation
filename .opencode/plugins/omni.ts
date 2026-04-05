// omni.ts — THE god-mode plugin for RESTO BOT
//
// Pattern: `tool.execute.before/after` acts as the bus across all other plugins,
// MCP servers, and built-in tools. Nothing calls plugin code directly — everything
// flows through hooks + a small set of custom tools.
//
// Responsibilities:
//   1. Secret injection via shell.env (never leaks into transcripts)
//   2. Secret redaction in ALL tool outputs (MCP + built-ins)
//   3. Audit log of every tool call → vault/60-Observability/tool-trace.jsonl
//   4. Post-edit nudges (workflows/*.json → run workflow-audit)
//   5. Session compaction prompt with RESTO BOT state
//   6. Session lifecycle logs → vault/60-Observability/
//   7. Custom tools: restaurant_status, vault_append, nid_create, repo_snapshot

import type { Plugin } from "@opencode-ai/plugin";
import { appendFile, mkdir, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";

const VAULT = "./vault";
const OBS = join(VAULT, "60-Observability");

// ────────────────────────────────────────────────────────────────────────────
// Utilities
// ────────────────────────────────────────────────────────────────────────────
const SECRET_PATTERNS: RegExp[] = [
  /sk-[a-zA-Z0-9]{20,}/g, // OpenAI / generic
  /sk-or-[a-zA-Z0-9-]{20,}/g, // OpenRouter
  /ghp_[a-zA-Z0-9]{36}/g, // GitHub PAT
  /gho_[a-zA-Z0-9]{36}/g, // GitHub OAuth
  /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}/g, // JWT
  /postgres(ql)?:\/\/[^:\s]+:[^@\s]+@/g, // Postgres URI creds
];

function redact(input: string): string {
  let out = input;
  for (const rx of SECRET_PATTERNS) out = out.replace(rx, "[REDACTED]");
  return out;
}

function deepRedact(val: unknown): unknown {
  if (typeof val === "string") return redact(val);
  if (Array.isArray(val)) return val.map(deepRedact);
  if (val && typeof val === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(val)) out[k] = deepRedact(v);
    return out;
  }
  return val;
}

function stamp(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}`;
}

async function ensureDir(p: string) {
  if (!existsSync(p)) await mkdir(p, { recursive: true });
}

async function traceLog(entry: Record<string, unknown>) {
  await ensureDir(OBS);
  await appendFile(
    join(OBS, "tool-trace.jsonl"),
    JSON.stringify({ ts: new Date().toISOString(), ...entry }) + "\n"
  );
}

// ────────────────────────────────────────────────────────────────────────────
// Plugin
// ────────────────────────────────────────────────────────────────────────────
const plugin: Plugin = async ({ $ }) => {
  return {
    // ── Inject env into every shell call (safe: never appears in transcript) ──
    "shell.env": async (env: Record<string, string>) => ({
      ...env,
      PROJECT: "resto-bot",
      VAULT_PATH: VAULT,
      // Pull from host env — values don't get serialized into chat
      DATABASE_URL: process.env.DATABASE_URL ?? env.DATABASE_URL ?? "",
      N8N_API_KEY: process.env.N8N_API_KEY ?? env.N8N_API_KEY ?? "",
      OPENROUTER_API_KEY: process.env.OPENROUTER_API_KEY ?? env.OPENROUTER_API_KEY ?? "",
    }),

    // ── Bus: intercept EVERY tool call (built-in, MCP, other plugins) ──
    "tool.execute.before": async (input: any, output: any) => {
      const toolName = input?.tool ?? "unknown";
      const args = output?.args ?? {};

      // Block reads of secret files (defense in depth over permission rules)
      if (toolName === "read" || toolName === "bash") {
        const blob = JSON.stringify(args);
        if (/\/\.env(\s|$|")|\.pem["\s]|\.key["\s]|\/secrets\//.test(blob)) {
          throw new Error(
            `[omni] Blocked access to secret file: ${blob.slice(0, 120)}`
          );
        }
      }

      await traceLog({ phase: "before", tool: toolName, args: deepRedact(args) });
    },

    "tool.execute.after": async (input: any, output: any) => {
      const toolName = input?.tool ?? "unknown";

      // Redact secrets from tool outputs before they reach the model
      if (output && typeof output === "object" && "output" in output) {
        output.output = deepRedact(output.output);
      }

      await traceLog({
        phase: "after",
        tool: toolName,
        ok: !output?.error,
      });

      // Post-edit nudges for critical paths
      if (toolName === "edit" || toolName === "write") {
        const path: string = (output?.args as any)?.filePath ?? "";
        if (/workflows\/.*\.json$/.test(path)) {
          await ensureDir(OBS);
          await appendFile(
            join(OBS, "nudges.log"),
            `[${new Date().toISOString()}] Edited ${path} → run /workflow-audit\n`
          );
        }
        if (/db\/migrations\/.*\.sql$/.test(path)) {
          await appendFile(
            join(OBS, "nudges.log"),
            `[${new Date().toISOString()}] Edited migration ${path} → run /db-inspect\n`
          );
        }
      }
    },

    // ── Session lifecycle ──
    event: async ({ event }: any) => {
      if (event.type === "session.end" || event.type === "session.idle") {
        await ensureDir(OBS);
        const path = join(OBS, `Session-${stamp()}.md`);
        if (!existsSync(path)) {
          await writeFile(
            path,
            [
              "---",
              `date: ${new Date().toISOString()}`,
              `event: ${event.type}`,
              "type: session-log",
              "---",
              "",
              `# Session ${stamp()}`,
              "",
              "_(auto-stub — curate with /session-close)_",
              "",
            ].join("\n")
          );
        }
      }
      if (event.type === "session.error") {
        await ensureDir(OBS);
        await appendFile(
          join(OBS, "errors.log"),
          `[${new Date().toISOString()}] ${JSON.stringify(event.properties ?? {})}\n`
        );
      }
    },

    // ── Inject RESTO BOT state into every compaction ──
    "experimental.session.compacting": async (input: any) => {
      let branch = "unknown";
      try {
        branch = (await $`git branch --show-current`.text()).trim();
      } catch {}
      const preamble = [
        "# RESTO BOT — persistent context (survives compaction)",
        "",
        `- Branch: \`${branch}\``,
        "- Stack: 12 Docker services, n8n 2.9.4, Strapi 5, PostgreSQL 15, Traefik 3.6.6",
        "- Current phase: 6 (Performance Tuning) — see .planning/STATE.md",
        "- Source of truth: .planning/ (roadmap), vault/ (sessions), repo (code)",
        "- Workflow: GSD — triage → map → spec → ADR → impl → test → close",
        "- Quality gate: 10-loop (lint, types, tests, build, DB, compose, docs, security, perf, rollback)",
        "",
      ].join("\n");
      return {
        ...input,
        prompt: preamble + "\n\n" + (input?.prompt ?? ""),
      };
    },

    // ── Custom tools exposed to every agent ──
    tool: {
      restaurant_status: {
        description:
          "Fan-out health check: git branch, docker compose status, vault active NIDs.",
        args: {},
        execute: async () => {
          const branch = (await $`git branch --show-current`.text()).trim();
          const gitStatus = (await $`git status --short`.text()).trim();
          let docker = "(docker not available)";
          try {
            docker = (await $`docker compose ps --format "table {{.Service}}\t{{.Status}}"`.text()).trim();
          } catch {}
          return {
            branch,
            git_dirty: gitStatus || "clean",
            docker,
            vault_path: VAULT,
            timestamp: new Date().toISOString(),
          };
        },
      },

      vault_append: {
        description: "Append markdown content to a file under vault/. Creates dirs.",
        args: {
          path: { type: "string", description: "Relative to vault/" },
          content: { type: "string" },
        },
        execute: async (args: { path: string; content: string }) => {
          const full = join(VAULT, args.path);
          await ensureDir(dirname(full));
          await appendFile(full, `\n${args.content}\n`);
          return { ok: true, path: full };
        },
      },

      nid_create: {
        description: "Create a new NID note in vault/10-Queue/.",
        args: {
          slug: { type: "string" },
          title: { type: "string" },
          kind: { type: "string", description: "feature|bug|chore|spike|ops" },
        },
        execute: async (args: { slug: string; title: string; kind: string }) => {
          const nid = `${stamp()}-${args.slug}`;
          const path = join(VAULT, "10-Queue", `${nid}.md`);
          await ensureDir(dirname(path));
          const body = [
            "---",
            `nid: ${nid}`,
            `title: "${args.title}"`,
            `kind: ${args.kind}`,
            "status: queued",
            `created_at: ${new Date().toISOString()}`,
            `updated_at: ${new Date().toISOString()}`,
            "---",
            "",
            `# ${args.title}`,
            "",
            "## Problem\n\n## Outcome\n\n## Scope\n",
          ].join("\n");
          await writeFile(path, body, { flag: "wx" });
          return { nid, path };
        },
      },

      repo_snapshot: {
        description: "Compact repo snapshot: branch, status, recent commits, tree.",
        args: {},
        execute: async () => ({
          branch: (await $`git branch --show-current`.text()).trim(),
          status: (await $`git status --short`.text()).trim() || "(clean)",
          recent_commits: (await $`git log --oneline -10`.text()).trim(),
        }),
      },
    },
  };
};

export default plugin;
