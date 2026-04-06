/**
 * Skill: SRE Operations (Ralphé)
 * Handles infrastructure health, n8n debugging, and database management.
 * Activates 'ops' plugin bundle on-demand.
 */
export async function checkVpsHealth(agent: any) {
  await agent.runCommand("plugin load ops");
  return await agent.runCommand("!vps-health");
}

export async function debugN8nExecution(agent: any, executionId: string) {
  await agent.runCommand("plugin load ops");
  return await agent.runCommand(`!n8n-exec-fix ${executionId}`);
}
