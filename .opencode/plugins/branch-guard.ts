// branch-guard.ts
// Blocks dangerous git operations & protects main/master from direct pushes.

import type { Plugin } from "@opencode-ai/plugin";

const DANGEROUS_PATTERNS = [
  /git\s+push\s+(--force|-f)\s+.*\b(main|master)\b/,
  /git\s+reset\s+--hard\s+origin\/(main|master)/,
  /git\s+branch\s+-D\s+(main|master)/,
  /git\s+checkout\s+(main|master)\s+--/,
  /git\s+push\s+.*--force-with-lease.*\b(main|master)\b/,
];

const plugin: Plugin = async ({ $ }) => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "bash") return;
      const cmd: string = (output.args as any)?.command ?? "";
      for (const pat of DANGEROUS_PATTERNS) {
        if (pat.test(cmd)) {
          throw new Error(
            `[branch-guard] Blocked dangerous git op against main/master: "${cmd}". ` +
              `If intentional, run manually outside OpenCode.`
          );
        }
      }
      // Warn if not on a feature branch when committing
      if (/git\s+commit/.test(cmd)) {
        try {
          const branch = (await $`git branch --show-current`.text()).trim();
          if (branch === "main" || branch === "master") {
            throw new Error(
              `[branch-guard] Refusing to commit directly on '${branch}'. Create a feature branch first.`
            );
          }
        } catch (e) {
          if (e instanceof Error && e.message.startsWith("[branch-guard]")) throw e;
          // git not available, skip
        }
      }
    },
  };
};

export default plugin;
