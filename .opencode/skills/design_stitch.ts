/**
 * Skill: Design Stitch (Ralphé)
 * Handles UI/UX iterations using the Stitch remote MCP server.
 * Activates 'design' plugin bundle on-demand.
 */
export async function generateUi(agent: any, prompt: string) {
  await agent.runCommand("plugin load design");
  return await agent.mcpCall("stitch", "generate_screen", { prompt });
}

export async function editUi(agent: any, screenId: string, instruction: string) {
  await agent.runCommand("plugin load design");
  return await agent.mcpCall("stitch", "edit_screens", { selectedScreenIds: [screenId], prompt: instruction });
}
