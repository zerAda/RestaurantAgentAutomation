/**
 * G-06 FIX — Strapi Agent Chat Controller
 *
 * AIChatBubble.tsx calls POST /api/agent/chat but this endpoint did NOT EXIST.
 * Every admin AI chat was returning 404. This controller implements:
 *   1. Session upsert (find-or-create by session_id)
 *   2. Forward message to n8n W4_CORE via webhook
 *   3. Parse n8n response and map to Dashboard-expected format
 *   4. Log LLM usage in llm-usage-log for AiObservatoryView
 *   5. Save session summary for AiObservatoryView Session Matrix
 *
 * MCP TOOL REGISTRY: This controller also exposes a GET /api/agent/tools
 * endpoint that returns all available Strapi data tools for LLM agents.
 */

import { Context } from 'koa';

declare const strapi: any;

const N8N_WEBHOOK = process.env.N8N_INTERNAL_WEBHOOK || 'http://n8n-main:5678';

export default {
  /**
   * POST /api/agent/chat
   * Called by AIChatBubble on the Admin Dashboard and optionally by n8n AI agents.
   */
  async chat(ctx: any) {
    const { message, sessionId, confirm, feedbackScore } = ctx.request.body?.data || {};

    if (!message || typeof message !== 'string') {
      return ctx.badRequest('Missing message field');
    }

    const trimmedMsg = message.trim().substring(0, 2000); // Hard cap: no prompt injection via giant payloads
    const safeSessionId = String(sessionId || 'admin-default').substring(0, 128);

    // ── 1. Handle feedback-only messages ─────────────────────────────────────
    if (message === 'feedback' && feedbackScore !== undefined) {
      try {
        const existing = await strapi.entityService.findMany('api::agent-session.agent-session', {
          filters: { session_id: safeSessionId },
          limit: 1,
        });
        if (existing?.length > 0) {
          await strapi.entityService.update('api::agent-session.agent-session', existing[0].id, {
            data: { feedback_score: feedbackScore },
          });
        }
      } catch (e) {
        strapi.log.warn('[agent-chat] Could not save feedback:', e);
      }
      ctx.body = { data: { reply: 'Feedback noted.', actions: [] } };
      return;
    }

    // ── 2. Upsert session ──────────────────────────────────────────────────────
    let session: any = null;
    try {
      const sessions = await strapi.entityService.findMany('api::agent-session.agent-session', {
        filters: { session_id: safeSessionId },
        limit: 1,
      });

      const adminUser = (ctx.state?.user?.email || ctx.state?.user?.username || 'unknown').substring(0, 128);

      if (sessions?.length > 0) {
        session = await strapi.entityService.update('api::agent-session.agent-session', sessions[0].id, {
          data: {
            last_message: trimmedMsg,
            messages_count: (sessions[0].messages_count || 0) + 1,
          },
        });
      } else {
        session = await strapi.entityService.create('api::agent-session.agent-session', {
          data: {
            session_id: safeSessionId,
            admin_user: adminUser,
            last_message: trimmedMsg,
            messages_count: 1,
          },
        });
      }
    } catch (e) {
      strapi.log.warn('[agent-chat] Session upsert failed (non-fatal):', e);
    }

    // ── 3. Forward to n8n W4_CORE ─────────────────────────────────────────────
    const startTime = Date.now();
    let n8nReply = 'Directive reçue. Traitement en cours...';
    let n8nActions: unknown[] = [];
    let n8nSuccess = true;
    let n8nError = '';

    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 45000);

      const res = await fetch(`${N8N_WEBHOOK}/webhook/admin-agent`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: trimmedMsg,
          sessionId: safeSessionId,
          confirm: confirm || false,
          context: 'admin-dashboard',
          user: ctx.state?.user?.email || 'admin',
        }),
        signal: controller.signal,
      });
      clearTimeout(timeout);

      if (res.ok) {
        const data = await res.json();
        n8nReply = data.reply || data.message || data.response || 'Traitement terminé.';
        n8nActions = data.actions || [];
      } else {
        throw new Error(`n8n HTTP ${res.status}`);
      }
    } catch (e: unknown) {
      n8nSuccess = false;
      n8nError = e instanceof Error ? e.message : String(e);
      strapi.log.error('[agent-chat] n8n call failed:', n8nError);
      n8nReply = `⚠️ Le neurone AI est temporairement indisponible (${n8nError}). Réessayez dans un instant.`;
    }

    const latencyMs = Date.now() - startTime;

    // ── 4. Log LLM usage (best-effort) ────────────────────────────────────────
    try {
      await strapi.entityService.create('api::llm-usage-log.llm-usage-log', {
        data: {
          workflow_id: 'admin-agent-chat',
          model: 'admin-chat-proxy',
          tokens_in: Math.ceil(trimmedMsg.length / 4),
          tokens_out: Math.ceil(n8nReply.length / 4),
          cost_usd: 0, // Cost tracked by n8n W4 internally
          latency_ms: latencyMs,
          success: n8nSuccess,
          error_message: n8nError || null,
          session_id: safeSessionId,
        },
      });
    } catch (e) {
      strapi.log.warn('[agent-chat] LLM log failed (non-fatal):', e);
    }

    // ── 5. Update session summary ──────────────────────────────────────────────
    if (session?.id && n8nSuccess) {
      try {
        await strapi.entityService.update('api::agent-session.agent-session', session.id, {
          data: {
            last_reply: n8nReply.substring(0, 1000),
            summary: `Dernière interaction: "${trimmedMsg.substring(0, 80)}..."`,
          },
        });
      } catch (e) {
        strapi.log.warn('[agent-chat] Session summary update failed (non-fatal):', e);
      }
    }

    // ── 6. Return Dashboard-compatible response ────────────────────────────────
    ctx.body = {
      data: {
        reply: n8nReply,
        actions: n8nActions,
        sessionId: safeSessionId,
        latencyMs,
      },
    };
  },

  /**
   * GET /api/agent/tools
   * MCP Tool Catalogue — returns all tools available to LLM agents.
   * n8n agents call this to discover what Strapi data they can query.
   */
  async tools(ctx: Context) {
    const tools = [
      {
        name: 'get_orders',
        description: 'Récupère les commandes récentes avec items, total, statut, et méthode de service',
        endpoint: '/api/orders',
        params: { sort: 'createdAt:desc', 'pagination[limit]': 50, populate: 'order_items,customer,driver' },
        schema: { status: 'pending|confirmed|preparing|ready|delivered|cancelled', total_amount: 'DA' },
      },
      {
        name: 'get_products',
        description: 'Récupère le catalogue produits avec prix, disponibilité, catégorie, et assets créatifs',
        endpoint: '/api/products',
        params: { populate: 'creative_assets,category', 'pagination[limit]': 100 },
      },
      {
        name: 'get_customers',
        description: 'Récupère les profils clients avec tier fidélité, historique commandes, et préférences',
        endpoint: '/api/customers',
        params: { sort: 'loyalty_points:desc', 'pagination[limit]': 50, populate: 'orders' },
      },
      {
        name: 'get_ingredients',
        description: 'Vérifie le stock des ingrédients, les niveaux d alertes, et les fournisseurs',
        endpoint: '/api/ingredients',
        params: { populate: 'supplier', 'pagination[limit]': 100 },
      },
      {
        name: 'get_ai_learnings',
        description: 'Récupère les insights IA: meilleur canal, heures de pointe, recommandations marketing',
        endpoint: '/api/ai-learnings',
        params: { sort: 'generated_at:desc', 'pagination[limit]': 5 },
      },
      {
        name: 'get_funnel_events',
        description: 'Analyse des événements funnel: conversions, drop-offs, et métriques de rétention',
        endpoint: '/api/funnel-events',
        params: { sort: 'createdAt:desc', 'pagination[limit]': 200 },
      },
      {
        name: 'get_workflow_errors',
        description: 'Erreurs des workflows n8n: nom, message, timestamp, et workflow ID',
        endpoint: '/api/workflow-errors',
        params: { sort: 'createdAt:desc', 'pagination[limit]': 20 },
      },
      {
        name: 'update_order_status',
        description: 'Met à jour le statut d une commande (preparing, ready, cancelled)',
        endpoint: '/api/orders/:documentId',
        method: 'PUT',
        body: { status: 'pending|confirmed|preparing|ready|delivered|cancelled' },
      },
      {
        name: 'get_llm_usage',
        description: 'Statistiques d utilisation LLM: coûts, latence, taux de succès par workflow',
        endpoint: '/api/llm-usage-logs',
        params: { sort: 'createdAt:desc', 'pagination[limit]': 100 },
      },
      {
        name: 'get_marketing_campaigns',
        description: 'Campagnes marketing actives: budget, performance, canal, et codes promo',
        endpoint: '/api/marketing-campaigns',
        params: { 'pagination[limit]': 20 },
      },
    ];

    ctx.body = {
      data: {
        tools,
        version: '1.0',
        baseUrl: process.env.STRAPI_API_URL || `http://localhost:1337`,
        auth: 'Authorization: Bearer <STRAPI_API_TOKEN>',
        note: 'All endpoints require a valid Strapi API token. POST /api/agent/chat for conversational AI.',
      },
    };
  },
};
