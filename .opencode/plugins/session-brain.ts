// session-brain.ts
// Auto-writes session summaries & NID updates to the Obsidian vault.
// Runs on session end + after significant tool-use batches.

import type { Plugin } from "@opencode-ai/plugin";
import { writeFile, mkdir, appendFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";

const VAULT = "./vault";
const OBS_DIR = join(VAULT, "60-Observability");

function nowStamp(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}`;
}

const plugin: Plugin = async ({ app, client, $ }) => {
  return {
    event: async ({ event }) => {
      // Persist session end summaries
      if (event.type === "session.end") {
        if (!existsSync(OBS_DIR)) {
          await mkdir(OBS_DIR, { recursive: true });
        }
        const stamp = nowStamp();
        const path = join(OBS_DIR, `Session-${stamp}.md`);
        const content = [
          "---",
          `date: ${new Date().toISOString()}`,
          `session_id: ${event.properties?.sessionID ?? "unknown"}`,
          "type: session-log",
          "---",
          "",
          `# Session ${stamp}`,
          "",
          "## Summary",
          "_(auto-generated placeholder — curate with /session-close)_",
          "",
        ].join("\n");
        try {
          await writeFile(path, content, { flag: "wx" });
        } catch {
          // file exists, skip
        }
      }

      // Log errors to vault for later triage
      if (event.type === "session.error") {
        const logPath = join(OBS_DIR, "errors.log");
        if (!existsSync(OBS_DIR)) await mkdir(OBS_DIR, { recursive: true });
        await appendFile(
          logPath,
          `[${new Date().toISOString()}] ${JSON.stringify(event.properties ?? {})}\n`
        );
      }
    },
  };
};

export default plugin;
