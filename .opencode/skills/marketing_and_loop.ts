/**
 * Skill: Marketing Studio & Loop (Ralphé)
 * Handles omnichannel attribution and ROI tracking.
 * Triggers the Tracking Loop on n8n.
 */
export async function triggerTrackingLoop(agent: any) {
  await agent.runCommand("plugin load ops");
  return await agent.runCommand("!ralphe-loop");
}

export async function checkRoi(agent: any) {
  await agent.runCommand("plugin load ops");
  const data = await agent.runCommand("ssh deploy@72.60.190.192 'echo \"SELECT date, orders_count, roi FROM marketing_stats ORDER BY date DESC LIMIT 7;\" | docker exec -i current-postgres-1 psql -U n8n -d n8n'");
  return data;
}

export async function tiktokSync(agent: any) {
  await agent.runCommand("plugin load ops");
  return await agent.runCommand("curl -X POST https://srv1258231.hstgr.cloud/webhooks/tiktok-sync");
}
