/**
 * Skill: SRE Guardian (Ralphé)
 * Handles VPS infrastructure health, disk management, and container watchdogs.
 * Interacts with scripts/ops/*.sh and Hostinger VPS (72.60.190.192).
 */
export async function checkSystemHealth(agent: any) {
  await agent.runCommand("plugin load ops");
  return await agent.runCommand("!vps-health");
}

export async function diskCleanup(agent: any) {
  await agent.runCommand("plugin load ops");
  const disk = await agent.runCommand("!check-disk");
  if (disk.includes("85%")) {
    await agent.runCommand("ssh deploy@72.60.190.192 'docker system prune -af'");
  }
  return disk;
}

export async function deepHealthCheck(agent: any) {
  await agent.runCommand("plugin load ops");
  return await agent.runCommand("ssh deploy@72.60.190.192 'bash scripts/deep-health-check.sh'");
}
