/**
 * REMOVED: This file previously registered a DUPLICATE /agent/chat route with auth: false.
 * The canonical route is in src/extensions/agent-chat/routes/agent-chat.ts with proper scoped auth.
 * 
 * P0 SECURITY FIX: This duplicate was non-deterministic — Strapi load order decided which
 * handler won. The system-config version had auth: false with manual JWT parsing,
 * while the extensions version uses proper Strapi middleware auth with scoped permissions.
 * 
 * DO NOT re-add routes here. Use src/extensions/agent-chat/ for all agent endpoints.
 */
export default {
    routes: [],
};
