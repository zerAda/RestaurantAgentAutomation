// branch-guard.ts — blocks destructive git ops against main/master
// Runs FIRST in the tool.execute.before chain.

import type { Plugin } from "@opencode-ai/plugin";

const DANGEROUS = [
  /git\s+push\s+(--force|-f|--force-with-lease)\s+.*\b(main|master)\b/,
  /git\s+reset\s+--hard\s+origin\/(main|master)/,
  /git\s+branch\s+-D\s+(main|master)/,
  /git\s+checkout\s+(main|master)\s+--/,
  /git\s+clean\s+-[fxd]+/,
];

const plugin: Plugin = async ({ $ }) => ({
  "tool.execute.before": async (input: any, output: any) => {
    if (input?.tool !== "bash") return;
    const cmd: string = output?.args?.command ?? "";

    for (const pat of DANGEROUS) {
      if (pat.test(cmd)) {
        throw new Error(
          `[branch-guard] Blocked dangerous op: "${cmd}". Run manually outside OpenCode if intentional.`
        );
      }
    }

    // Block direct commits to main/master
    if (/git\s+commit\b/.test(cmd) && !/--amend/.test(cmd)) {
      try {
        const branch = (await $`git branch --show-current`.text()).trim();
        if (branch === "main" || branch === "master") {
          throw new Error(
            `[branch-guard] Refusing to commit on '${branch}'. Create a feature branch first.`
          );
        }
      } catch (e) {
        if (e instanceof Error && e.message.startsWith("[branch-guard]")) throw e;
      }
    }
  },
});

export default plugin;
