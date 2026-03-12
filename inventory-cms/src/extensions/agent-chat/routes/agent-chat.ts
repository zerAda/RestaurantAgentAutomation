/**
 * Routes for the Agent Chat extension.
 * Registers:
 *   POST /api/agent/chat   — AI chat endpoint for AIChatBubble + n8n agents
 *   GET  /api/agent/tools  — MCP tool catalogue for LLM agents
 */
export default {
  routes: [
    {
      method: 'POST',
      path: '/agent/chat',
      handler: 'agent-chat.chat',
      config: {
        auth: {
          // Requires admin JWT (set by AIChatBubble) OR API token (for n8n agents)
          // Do NOT set auth: false — this endpoint has access to business data
          scope: ['api::agent-session.agent-session.create'],
        },
        middlewares: ['global::rate-limiter'],
        description: 'AI chat endpoint for Admin Dashboard and n8n LLM agents',
      },
    },
    {
      method: 'GET',
      path: '/agent/tools',
      handler: 'agent-chat.tools',
      config: {
        auth: {
          scope: ['api::agent-session.agent-session.find'],
        },
        description: 'MCP tool catalogue — returns all available Strapi data tools for LLM agents',
      },
    },
  ],
};
