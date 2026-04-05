// repo-tools.ts
// Exposes custom tools: repo_snapshot, vault_append, nid_create.

import type { Plugin } from "@opencode-ai/plugin";
import { appendFile, mkdir, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";

const plugin: Plugin = async ({ $ }) => {
  return {
    tool: {
      repo_snapshot: {
        description: "Return a compact snapshot of repo: git branch, status, recent log, top-level tree.",
        args: {},
        execute: async () => {
          const branch = (await $`git branch --show-current`.text()).trim();
          const status = (await $`git status --short`.text()).trim();
          const log = (await $`git log --oneline -10`.text()).trim();
          const tree = (await $`ls -la`.text()).trim();
          return {
            branch,
            status: status || "(clean)",
            recent_commits: log,
            tree,
          };
        },
      },

      vault_append: {
        description: "Append markdown content to a file in vault/. Creates dirs as needed.",
        args: {
          path: { type: "string", description: "Path relative to vault/, e.g. 90-Index/Active NIDs.md" },
          content: { type: "string", description: "Markdown content to append" },
        },
        execute: async (args: { path: string; content: string }) => {
          const full = join("./vault", args.path);
          const dir = dirname(full);
          if (!existsSync(dir)) await mkdir(dir, { recursive: true });
          await appendFile(full, `\n${args.content}\n`);
          return { ok: true, path: full };
        },
      },

      nid_create: {
        description: "Create a new NID note in vault/10-Queue/ with a slug.",
        args: {
          slug: { type: "string", description: "short-kebab-slug" },
          title: { type: "string" },
          kind: { type: "string", description: "feature|bug|chore|spike|ops" },
        },
        execute: async (args: { slug: string; title: string; kind: string }) => {
          const d = new Date();
          const pad = (n: number) => String(n).padStart(2, "0");
          const stamp = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}`;
          const nid = `${stamp}-${args.slug}`;
          const path = join("./vault/10-Queue", `${nid}.md`);
          const front = [
            "---",
            `nid: ${nid}`,
            `title: "${args.title}"`,
            `kind: ${args.kind}`,
            "status: queued",
            `created_at: ${d.toISOString()}`,
            `updated_at: ${d.toISOString()}`,
            "---",
            "",
            `# ${args.title}`,
            "",
            "## Problem",
            "",
            "## Outcome",
            "",
          ].join("\n");
          if (!existsSync("./vault/10-Queue")) {
            await mkdir("./vault/10-Queue", { recursive: true });
          }
          await writeFile(path, front, { flag: "wx" });
          return { nid, path };
        },
      },
    },
  };
};

export default plugin;
