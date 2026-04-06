/**
 * Skill: Diamond Deploy (Ralphé)
 * Handles git-deploy.sh, vps-sync.sh, and Post-deploy Smoke Tests.
 */
export async function syncAndSync(agent: any, service: string) {
  await agent.runCommand("plugin load vcs");
  await agent.runCommand("plugin load ops");
  await agent.runCommand(`bash scripts/vps-sync.sh --sync ${service}`);
  return await agent.runCommand("bash scripts/smoke.sh");
}

export async function fullDeploy(agent: any) {
  await agent.runCommand("plugin load vcs");
  await agent.runCommand("plugin load ops");
  return await agent.runCommand("ssh deploy@72.60.190.192 'bash /opt/resto/repo/scripts/git-deploy.sh'");
}

export async function runSreIntegrityGate(agent: any) {
  await agent.runCommand("plugin load ops");
  return await agent.runCommand("bash scripts/integrity_gate.sh");
}
