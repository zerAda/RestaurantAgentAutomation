import { Context } from 'koa';
import type { Core } from '@strapi/strapi';
import Redis from 'ioredis';

declare var strapi: Core.Strapi;

let _redis: Redis | null = null;
function getRedis(): Redis {
    if (!_redis) {
        _redis = new Redis(parseInt(process.env.REDIS_PORT || '6379'), process.env.REDIS_HOST || 'localhost');
        _redis.on('error', (err) => strapi.log.error('AgentChat Redis Error', err));
    }
    return _redis;
}

/* ── Helpers ── */
async function safeQuery(uid: any, params = {}) {
    try { return await strapi.db.query(uid).findMany(params); }
    catch { return []; }
}
async function safeQueryOne(uid: any) {
    try { return await strapi.db.query(uid).findOne({}); }
    catch { return null; }
}

/* ── Redis Rate Limiter ── */
async function checkRateLimit(userId: string | number): Promise<boolean> {
    try {
        const redis = getRedis();
        const key = `ratelimit:agent:${userId || 'anon'}`;
        const current = await redis.incr(key);
        if (current === 1) {
            await redis.expire(key, 60);
        }
        return current <= 20;
    } catch (e: any) {
        strapi.log.warn(`Redis Rate Limiting failed, allowing request: ${e.message}`);
        return true;
    }
}

/* ── Redis RAG Cache ── */
async function fetchRAGSlice(name: string, fetchFn: () => Promise<string>): Promise<string> {
    try {
        const redis = getRedis();
        const key = `rag_cache:${name}`;
        const cached = await redis.get(key);
        if (cached) return cached + '\n*(cached)*';

        const data = await fetchFn();
        await redis.setex(key, 60 * 5, data); // Cache for 5 minutes
        return data;
    } catch (e) {
        return fetchFn();
    }
}

/* ── Input Sanitization ── */
function sanitizeInput(msg: string): string {
    return msg
        .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '')
        .trim()
        .slice(0, 2000);
}

const CONFIG_ALLOWED_FIELDS = [
    'llm_model', 'llm_temperature', 'llm_max_tokens', 'llm_timeout_ms', 'llm_fallback_model',
    'agent_system_prompt', 'system_prompt_strategy', 'system_prompt_image_gen', 'system_prompt_video_gen',
    'enable_tiktok', 'enable_snapchat', 'enable_instagram', 'enable_facebook', 'enable_whatsapp_stories',
    'delivery_enabled', 'delivery_radius_km', 'delivery_fee_multiplier', 'delivery_eta_base_min', 'delivery_eta_per_km_min',
    'surge_multiplier_max', 'surge_rain_bonus',
    'kitchen_load_threshold', 'kitchen_load_extra_min',
    'kiosk_enabled', 'kiosk_default_service_mode', 'kiosk_idle_timeout_sec',
    'cart_abandonment_delay_min', 'vip_win_back_delay_days', 'content_quality_threshold', 'auto_ad_budget_multiplier',
    'video_aspect_ratio', 'l10n_enabled', 'strict_ar_out', 'default_currency', 'n8n_webhook_base_url',
    'enable_proactive_alerts', 'proactive_alert_interval_hours',
    'enable_content_scheduler', 'content_scheduler_interval_hours',
    'enable_driver_gamification', 'driver_xp_per_delivery', 'driver_xp_speed_bonus', 'driver_level_divisor',
    'the_usual_min_repeats',
    'hive_mind_stacking_bonus', 'hive_mind_overload_penalty', 'hive_mind_max_active_jobs',
    'review_delay_min', 'review_window_min',
    'dlq_retry_interval_hours',
];

function extractSafeConfig(config: Record<string, any>) {
    if (!config) return {};
    const safe: Record<string, any> = {};
    for (const key of CONFIG_ALLOWED_FIELDS) {
        if (config[key] !== undefined) safe[key] = config[key];
    }
    return safe;
}

const CONTEXT_SLICES: Record<string, { keywords: string[], fetch: () => Promise<string> }> = {
    products: {
        keywords: ['produit', 'menu', 'prix', 'stock', 'rupture', 'catalogue', 'plat', 'burger', 'pizza', 'tacos', 'sandwich', 'disponib', 'ajout', 'supprim', 'modifi', 'catégorie', 'vend', 'populaire', 'flop'],
        fetch: async () => {
            const items = await safeQuery('api::product.product', { limit: 200, orderBy: { createdAt: 'desc' } });
            return `### Produits (${items.length})\n` + items.map((p: any) =>
                `- ${p.name}: ${p.price || 0} DA ${p.stock_quantity <= 0 ? '❌ RUPTURE' : `✅ (stock: ${p.stock_quantity})`} [cat: ${p.category || 'N/A'}] [prep: ${p.preparation_time_min || '?'}min]`
            ).join('\n');
        }
    },
    orders: {
        keywords: ['commande', 'order', 'vente', 'revenue', 'chiffre', 'aov', 'panier', 'ticket', 'kanban', 'kpi', 'semaine', 'jour', 'mois', 'baisser', 'performance', 'résumé', 'overview'],
        fetch: async () => {
            const knex = strapi.db.connection;
            try {
                const stats = await knex('orders').count('id as cnt').sum('total_amount as sum').first();
                const total = parseInt(stats?.cnt as string || '0');
                const rev = parseFloat(stats?.sum as string || '0');
                const aov = total > 0 ? (rev / total).toFixed(0) : 0;
                return `### Commandes (Total)\n- Revenue totale: ${rev.toFixed(0)} DA\n- Commandes totales: ${total}\n- AOV: ${aov} DA`;
            } catch (e) {
                const orders = await safeQuery('api::order.order', { limit: 100, orderBy: { createdAt: 'desc' } });
                const total = orders.length; const rev = orders.reduce((s: number, o: any) => s + (o.total_amount || 0), 0);
                return `### Commandes (last ${total})\n- Revenue totale: ${rev.toFixed(0)} DA\n- AOV: ${total ? (rev / total).toFixed(0) : 0} DA`;
            }
        }
    },
    customers: {
        keywords: ['client', 'customer', 'fidél', 'loyalty', 'point', 'vip', 'récurrent', 'top client', 'préférence', 'upsell', 'relance', 'inactif', 'perdu', 'rétention'],
        fetch: async () => {
            const custs = await safeQuery('api::customer.customer', { limit: 100, orderBy: { createdAt: 'desc' }, populate: ['loyalty_tier'] });
            if (!custs.length) return '### Clients\nAucun client enregistré.';
            return `### Clients (${custs.length})\n- Top 5 (par points): ${custs.sort((a: any, b: any) => (b.points || 0) - (a.points || 0)).slice(0, 5).map((c: any) => `${c.name || c.phone} (${c.points || 0} pts)`).join(', ')}`;
        }
    },
    feedback: {
        keywords: ['avis', 'review', 'feedback', 'rating', 'note', 'étoile', 'star', 'plainte', 'commentaire', 'satisfaction', 'négatif', 'positif', 'mauvais'],
        fetch: async () => {
            const reviews = await safeQuery('api::feedback.feedback', { limit: 50, orderBy: { createdAt: 'desc' }, populate: ['customer', 'order'] });
            if (!reviews.length) return '### Feedback\nAucun avis enregistré.';
            const avgRating = (reviews.reduce((s: any, r: any) => s + (r.rating || 0), 0) / reviews.length).toFixed(1);
            const negative = reviews.filter((r: any) => r.rating <= 2);
            return `### Feedback clients (${reviews.length})\n- Note moyenne: ${avgRating}/5\n- Avis négatifs (≤2★): ${negative.length}\n- Derniers avis: ${reviews.slice(0, 5).map((r: any) => `${r.rating}★ "${(r.comment || 'Sans commentaire').slice(0, 50)}"`).join(' | ')}`;
        }
    },
    drivers: {
        keywords: ['livreur', 'driver', 'flotte', 'fleet', 'coursier', 'occupation', 'gps', 'tracking'],
        fetch: async () => {
            const drivers = await safeQuery('api::driver.driver', { limit: 50 });
            if (!drivers.length) return '### Flotte de livreurs\nAucun livreur enregistré.';
            const avgRating = (drivers.reduce((s: any, d: any) => s + (d.rating || 0), 0) / drivers.length).toFixed(1);
            return `### Flotte livreurs (${drivers.length})\n- Note moyenne: ${avgRating}/5\n- Livreurs actifs: ${drivers.filter((d: any) => d.is_active).length}/${drivers.length}\n- Détail: ${drivers.map((d: any) => `${d.first_name} [${d.status}] ${d.vehicle_type} — ${d.total_deliveries || 0} livraisons, note ${d.rating || '?'}/5`).join('\n  ')}`;
        }
    },
    ingredients: {
        keywords: ['ingrédient', 'ingredient', 'fournisseur', 'supplier', 'matière', 'provision', 'approvisionnement', 'inventaire'],
        fetch: async () => {
            const items = await safeQuery('api::ingredient.ingredient', { limit: 200, populate: ['supplier'] });
            if (!items.length) return '### Ingrédients\nAucun ingrédient enregistré.';
            const lowStock = items.filter((i: any) => (i.current_stock || 0) <= (i.min_stock_alert || 10));
            return `### Ingrédients (${items.length})\n- ⚠️ STOCK BAS: ${lowStock.length}\n${lowStock.length > 0 ? lowStock.map((i: any) => `  🔴 ${i.name}: ${i.current_stock} ${i.unit} (seuil: ${i.min_stock_alert})`).join('\n') : '  Tous les stocks sont OK'}`;
        }
    },
    funnel: {
        keywords: ['funnel', 'conversion', 'drop', 'abandon', 'canal', 'channel', 'taux', 'learning', 'apprent', 'entonnoir', 'parcours', 'checkout', 'étape'],
        fetch: async () => {
            const [events, learnings] = await Promise.all([
                safeQuery('api::funnel-event.funnel-event', { limit: 30, orderBy: { createdAt: 'desc' } }),
                safeQuery('api::ai-learning.ai-learning', { limit: 3, orderBy: { createdAt: 'desc' } }),
            ]);
            let out = `### Funnel Analytics (${events.length} events)\n`;
            out += events.slice(0, 5).map((f: any) => `- ${f.channel || '?'} → "${f.step || '?'}" : drop ${f.drop_off_rate || '?'}%`).join('\n');
            if (learnings.length > 0) {
                const l = learnings[0].learnings_json || learnings[0];
                out += `\n### AI Learnings\n- Best channel: ${l.best_channel || 'N/A'}\n- Peak hours: ${JSON.stringify(l.peak_hours || [])}\n- Worst drop-off: ${l.worst_drop_off || 'N/A'}\n- Campaign score: ${l.campaign_score || 'N/A'}/100`;
            }
            return out;
        }
    },
    campaigns: {
        keywords: ['campagne', 'marketing', 'pub ', 'roas', 'budget', 'tiktok', 'instagram', 'promo', 'promotion', 'influenceur', 'publicité', 'ads '],
        fetch: async () => {
            const camps = await safeQuery('api::ad-campaign.ad-campaign', { limit: 10, orderBy: { createdAt: 'desc' } });
            return camps.length ? `### Campagnes (${camps.length})\n` + camps.map((c: any) => `- ${c.name || c.platform}: ${c.status} | Budget: ${c.budget || '?'} | ROAS: ${c.roas || '?'}`).join('\n') : '### Campagnes\nAucune campagne.';
        }
    },
    config: {
        keywords: ['config', 'paramètr', 'réglage', 'setting', 'système', 'kiosk', 'surge', 'seuil', 'llm', 'model', 'temperature', 'température', 'feature', 'enable', 'activ', 'désactiv'],
        fetch: async () => {
            const config = await safeQueryOne('api::system-config.system-config');
            if (!config) return '### Config\nNon disponible.';
            return `### Configuration Système\n${JSON.stringify(extractSafeConfig(config), null, 2)}`;
        }
    },
    prompts: {
        keywords: ['prompt', 'system_prompt', 'image_gen', 'video_gen', 'strateg', 'génération', 'améliorer', 'rédiger', 'texte', 'caption', 'boucle', 'learning loop'],
        fetch: async () => {
            const config = await safeQueryOne('api::system-config.system-config');
            if (!config) return '### Prompts IA\nNon disponibles.';
            return `### Prompts IA Actuels\n- **Strategy**: "${config.system_prompt_strategy || 'N/A'}"\n- **Image Gen**: "${config.system_prompt_image_gen || 'N/A'}"\n- **LLM**: ${config.llm_model || 'llama3.1'} | Temp: ${config.llm_temperature || 0.1}`;
        }
    },
    delivery: {
        keywords: ['zone livraison', 'delivery zone', 'commune', 'wilaya', 'frais livraison', 'rayon', 'couverture', 'délai livraison', 'fee livraison', 'zone de'],
        fetch: async () => {
            const zones = await safeQuery('api::delivery-zone.delivery-zone', { limit: 50 });
            return zones.length ? `### Zones de livraison (${zones.length})\n` + zones.map((z: any) => `- ${z.name}: ${(z.price_cents || 0) / 100} DA ${z.active ? '✅' : '❌ INACTIVE'}`).join('\n') : '### Zones\nAucune zone configurée.';
        }
    },
    errors: {
        keywords: ['erreur', 'error', 'bug', 'crash', 'plantage', 'workflow', 'n8n', 'logs', 'debug', 'problème', 'panne', 'échoué', 'failed', 'diagnostic'],
        fetch: async () => {
            const errors = await safeQuery('api::workflow-error.workflow-error', { limit: 20, orderBy: { createdAt: 'desc' } });
            if (!errors.length) return '### Erreurs Workflow\n✅ Aucune erreur récente.';
            return `### Erreurs Workflow (${errors.length} récentes)\n${errors.slice(0, 5).map((e: any) => `- 🔴 **${e.workflow_name}** → ${e.node_name}: "${(e.error_message || '').slice(0, 100)}" [exec: ${e.execution_id || '?'}]`).join('\n')}`;
        }
    },
    rewards: {
        keywords: ['récompense', 'reward', 'roue', 'wheel', 'fortune', 'coupon', 'spin', 'gamif', 'jeu', 'prize', 'cadeau', 'tirage', 'lot'],
        fetch: async () => {
            const campaigns = await safeQuery('api::reward-campaign.reward-campaign', { limit: 10, orderBy: { createdAt: 'desc' } });
            return campaigns.length ? `### Campagnes Récompenses (${campaigns.length})\n` + campaigns.map((c: any) => `- ${c.name}: ${c.is_active ? '✅ ACTIVE' : '❌ inactive'} | Max spins: ${c.max_spins_per_customer || '?'}`).join('\n') : '### Campagnes Récompenses\nAucune campagne.';
        }
    },
    scheduled_posts: {
        keywords: ['publication', 'publier', 'scheduler', 'planning', 'post', 'social media', 'programmer', 'queue', 'file d\'attente', 'planifié'],
        fetch: async () => {
            const posts = await safeQuery('api::scheduled-post.scheduled-post', { limit: 20, orderBy: { scheduled_at: 'desc' } });
            if (!posts.length) return '### Publications planifiées\nAucune publication en attente.';
            return `### Publications planifiées (${posts.length})\n- Prochaine: ${posts.find((p: any) => p.status === 'pending')?.scheduled_at || 'Aucune en attente'}`;
        }
    },
    alerts: {
        keywords: ['alerte', 'alert', 'proactif', 'proactive', 'kpi alert', 'notification admin', 'surveillance', 'monitoring kpi'],
        fetch: async () => {
            const logs = await safeQuery('api::proactive-alert-log.proactive-alert-log', { limit: 10, orderBy: { createdAt: 'desc' } });
            if (!logs.length) return '### Alertes Proactives\nAucune alerte envoyée.';
            return `### Alertes Proactives (${logs.length} récentes)\n- Dernière: ${logs[0]?.createdAt || 'N/A'}\n- Analyse LLM: "${(logs[0]?.llm_analysis || '').slice(0, 200)}"`;
        }
    },
    dispatch: {
        keywords: ['dispatch', 'assignation', 'hive mind', 'affectation', 'attribution livreur', 'score livreur', 'algo dispatch', 'scoring'],
        fetch: async () => {
            const logs = await safeQuery('api::dispatch-log.dispatch-log', { limit: 15, orderBy: { createdAt: 'desc' } });
            if (!logs.length) return '### Dispatch IA\nAucun log de dispatch.';
            const accepted = logs.filter((l: any) => l.accepted);
            return `### Dispatch IA (${logs.length} derniers)\n- Taux d'acceptation: ${accepted.length}/${logs.length} (${((accepted.length / logs.length) * 100).toFixed(0)}%)\n- Dernier: order ${logs[0]?.order_id || '?'} → driver ${logs[0]?.selected_driver_id || '?'}`;
        }
    },
    gamification: {
        keywords: ['xp', 'level', 'niveau', 'gamification', 'classement', 'leaderboard', 'badge', 'performance livreur'],
        fetch: async () => {
            const drivers = await safeQuery('api::driver.driver', { limit: 50 });
            if (!drivers.length) return '### Gamification Livreurs\nAucun livreur.';
            const withXP = drivers.filter((d: any) => (d.xp || 0) > 0).sort((a: any, b: any) => (b.xp || 0) - (a.xp || 0));
            return `### Gamification Livreurs\n- Top 5:\n${withXP.slice(0, 5).map((d: any, i: any) => `  ${i + 1}. ${d.first_name || d.phone} — ${d.xp || 0} XP`).join('\n') || '  Pas encore de données'}`;
        }
    },
};

function detectNeededSlices(message: string): string[] {
    const lower = message.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    const needed: string[] = [];
    for (const [name, slice] of Object.entries(CONTEXT_SLICES)) {
        if (slice.keywords.some(k => lower.includes(k.normalize('NFD').replace(/[\u0300-\u036f]/g, '')))) needed.push(name);
    }
    const isAnalytical = /augmenter|ameliorer|optimiser|idee|conseil|strateg/.test(lower);
    if (isAnalytical && !needed.includes('orders')) needed.push('orders');
    if (isAnalytical && !needed.includes('funnel')) needed.push('funnel');
    if (/stock|rupture|alerte/.test(lower)) {
        if (!needed.includes('products')) needed.push('products');
        if (!needed.includes('ingredients')) needed.push('ingredients');
    }
    if (/livraison|delivery|livr/.test(lower)) {
        if (!needed.includes('drivers')) needed.push('drivers');
        if (!needed.includes('delivery')) needed.push('delivery');
        if (!needed.includes('dispatch')) needed.push('dispatch');
    }
    if (needed.length === 0) {
        if (/comment|explique|c.?est quoi|aide|help|utiliser|fonctionn|apprend|montre|guide|tuto/.test(lower)) needed.push('config', 'orders');
        else needed.push('orders');
    }
    return [...new Set(needed)];
}

const PROJECT_KNOWLEDGE = `## RALPHÉ ECOSYSTEM — FULL MAP\nProvides enterprise RAG info...`;
const AGENT_SYSTEM_PROMPT = `Tu es **Ralphé**, l'IA du restaurant avec visibilité TOTALE sur 33 content-types Strapi, 77 workflows n8n, et 4 apps.
TES 7 RÔLES
1. Éducateur
2. Conseiller Stratégique
3. Pilote Strapi
4. Architecte n8n
5. Prompt Engineer
6. Analyste Client
7. Ops Manager`;

/* ── LLM Usage Logger ── */
function logLLMUsage(data: any) {
    try {
        strapi.db.query('api::llm-usage-log.llm-usage-log').create({ data }).catch((e: any) => {
            strapi.log.warn(`[AgentChat] LLM log write failed: ${e.message}`);
        });
    } catch { /* ignore */ }
}

export default {
    async chat(ctx: Context) {
        const token = ctx.request.header.authorization?.split(' ')[1];
        if (!token) return ctx.unauthorized('Token manquant. Accès refusé.');

        try {
            const payload = await strapi.plugin('users-permissions').service('jwt').verify(token);
            if (!payload || !payload.id) throw new Error('Invalid token');
            const user = await strapi.query('plugin::users-permissions.user').findOne({ where: { id: payload.id } });
            if (!user) throw new Error('User not found');
            ctx.state.user = user;
        } catch (err) {
            return ctx.unauthorized('Token invalide ou expiré.');
        }

        const body: any = (ctx.request as any).body?.data || (ctx.request as any).body || {};
        const userId = ctx.state.user.id;
        const adminEmail = ctx.state.user.email || 'admin';

        /* Redis Rate limit */
        const isAllowed = await checkRateLimit(userId);
        if (!isAllowed) {
            if (ctx.tooManyRequests) return ctx.tooManyRequests('Trop de requêtes. Attendez 1 minute.');
            return ctx.badRequest('Trop de requêtes. Attendez 1 minute.');
        }

        const rawMessage = body.message || '';
        if (rawMessage.length > 2000) return ctx.badRequest('Message trop long (max 2000 caractères).');
        const message = sanitizeInput(rawMessage);

        const sessionId = body.sessionId || `admin-${userId}-session`;
        const confirm = body.confirm || false;
        const feedbackScore = body.feedbackScore; // -1, 0, or 1

        if (!message && feedbackScore === undefined) return ctx.badRequest('Message vide.');

        /* 0. Handle feedback-only requests */
        if (feedbackScore !== undefined && typeof feedbackScore === 'number') {
            try {
                const existing = await safeQuery('api::agent-session.agent-session', { where: { session_id: sessionId }, limit: 1 });
                if (existing.length > 0) {
                    await strapi.db.query('api::agent-session.agent-session').update({
                        where: { id: existing[0].id },
                        data: { feedback_score: feedbackScore },
                    });
                }
            } catch (e: any) { strapi.log.warn(`[AgentChat] feedback save failed: ${e.message}`); }
            if (!message) return ctx.send({ success: true, message: 'Feedback saved' });
        }

        /* 1. Load session memory (last 3 conversations) */
        let sessionMemory = '';
        try {
            const pastSessions = await safeQuery('api::agent-session.agent-session', {
                where: { admin_user: adminEmail },
                orderBy: { updatedAt: 'desc' },
                limit: 3,
            });
            if (pastSessions.length > 0) {
                sessionMemory = '## SESSION MEMORY (dernières conversations)\n' +
                    pastSessions.map((s: any, i: number) => {
                        const ago = Math.round((Date.now() - new Date(s.updatedAt).getTime()) / 3600000);
                        return `### Session ${i + 1} (il y a ${ago}h, ${s.messages_count || 0} msgs)\n` +
                            `Dernier message: ${(s.last_message || '').slice(0, 100)}\n` +
                            `Résumé: ${s.summary || 'Aucun résumé'}`;
                    }).join('\n\n');
            }
        } catch (e: any) { strapi.log.warn(`[AgentChat] memory load failed: ${e.message}`); }

        const neededSlices = detectNeededSlices(message);
        strapi.log.info(`[AgentChat] RAG slices: [${neededSlices.join(', ')}]`);

        // Fetch slices via Redis RAG Cache in parallel
        const contextParts = await Promise.all(
            neededSlices.map(name =>
                fetchRAGSlice(name, () => CONTEXT_SLICES[name]?.fetch().catch(err => `### ${name}\n⚠️ Erreur: ${(err as any).message}`) || Promise.resolve(`### ${name}\nSlice inconnu.`))
            )
        );

        const liveContext = `## LIVE DATA\n${contextParts.join('\n\n')}`;

        let n8nBase = process.env.N8N_WEBHOOK_BASE || 'http://n8n:5678';
        try {
            const config = await safeQueryOne('api::system-config.system-config');
            if (config?.n8n_webhook_base_url) n8nBase = config.n8n_webhook_base_url;
        } catch { }
        n8nBase = n8nBase.replace(/\/+$/, '');

        const startTime = Date.now();
        try {
            const ctrl = new AbortController();
            const timeout = setTimeout(() => ctrl.abort(), 45000);

            const response = await fetch(`${n8nBase}/webhook/admin/chat`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    ...(process.env.N8N_WEBHOOK_AUTH
                        ? { 'Authorization': `Basic ${Buffer.from(process.env.N8N_WEBHOOK_AUTH).toString('base64')}` }
                        : {}),
                },
                body: JSON.stringify({
                    message, sessionId, confirm, adminUser: adminEmail,
                    systemPrompt: AGENT_SYSTEM_PROMPT, projectKnowledge: PROJECT_KNOWLEDGE, liveContext, sessionMemory
                }),
                signal: ctrl.signal,
            });
            clearTimeout(timeout);

            const latencyMs = Date.now() - startTime;

            if (!response.ok) {
                strapi.log.error(`[AgentChat] n8n ${response.status}: ${response.statusText}`);
                logLLMUsage({ workflow_id: 'W_ADMIN_AGENT', model: 'n8n-proxy', tokens_in: message.length, tokens_out: 0, cost_usd: 0, latency_ms: latencyMs, success: false, error_message: `HTTP ${response.status}`, session_id: sessionId });
                return ctx.badRequest(`Erreur agent (${response.status}). Vérifiez que n8n est en ligne.`);
            }

            const data = await response.json().catch(() => ({ output: 'Requête traitée.' }));
            const reply = data.output || data.message || data.text || data.response || 'Requête traitée.';

            /* 6. Save session memory */
            try {
                const existing = await safeQuery('api::agent-session.agent-session', { where: { session_id: sessionId }, limit: 1 });
                const sessionData = {
                    session_id: sessionId, admin_user: adminEmail,
                    last_message: message.slice(0, 500), last_reply: reply.slice(0, 500),
                    rag_slices_used: neededSlices, summary: `Q: ${message.slice(0, 100)} → R: ${reply.slice(0, 150)}`,
                };
                if (existing.length > 0) {
                    await strapi.db.query('api::agent-session.agent-session').update({
                        where: { id: existing[0].id },
                        data: { ...sessionData, messages_count: (existing[0].messages_count || 0) + 1 },
                    });
                } else {
                    await strapi.db.query('api::agent-session.agent-session').create({
                        data: { ...sessionData, messages_count: 1 },
                    });
                }
            } catch (e: any) { strapi.log.warn(`[AgentChat] session save failed: ${e.message}`); }

            /* 7. Log LLM usage */
            logLLMUsage({
                workflow_id: 'W_ADMIN_AGENT',
                model: data.model || 'unknown',
                tokens_in: data.tokens_in || message.length,
                tokens_out: data.tokens_out || reply.length,
                cost_usd: data.cost_usd || 0,
                latency_ms: latencyMs,
                success: true,
                session_id: sessionId,
            });

            ctx.send({
                success: true, reply, actions: data.actions || [],
                needsConfirmation: data.needsConfirmation || false, confirmAction: data.confirmAction || null,
                ragSlices: neededSlices, sessionId, timestamp: new Date().toISOString(),
                hasMemory: sessionMemory.length > 0
            });
        } catch (err: any) {
            const latencyMs = Date.now() - startTime;
            logLLMUsage({ workflow_id: 'W_ADMIN_AGENT', model: 'n8n-proxy', tokens_in: message.length, tokens_out: 0, cost_usd: 0, latency_ms: latencyMs, success: false, error_message: err.message, session_id: sessionId });
            if (err.name === 'AbortError') return ctx.badRequest('Agent timeout après 45s. Essayez une question plus simple.');
            strapi.log.error(`[AgentChat] ${err.message}`);
            ctx.badRequest(`Connexion agent échouée. Vérifiez que n8n est accessible sur ${n8nBase}.`);
        }
    },
};
