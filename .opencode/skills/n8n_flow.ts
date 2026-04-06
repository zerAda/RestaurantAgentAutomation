/**
 * Skill: n8n Flow Master (Ralphé)
 * Handles workflow introspection, logs, and execution fixes for 97 workflows.
 */
export async function listRecentFailures(agent: any) {
  await agent.runCommand("plugin load ops");
  return await agent.runCommand("!n8n-exec-fix");
}

export async function patchWorkflow(agent: any, workflowPath: string) {
  await agent.runCommand("plugin load ops");
  return await agent.runCommand(`node scripts/patch_adapters.js ${workflowPath}`);
}

export async function checkWorkerStatus(agent: any) {
  await agent.runCommand("plugin load ops");
  return await agent.runCommand("!n8n-status");
}
