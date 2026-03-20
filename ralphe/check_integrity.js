// Simulate integrity_gate.sh checks using Node.js (faster on Windows)
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
process.chdir(ROOT);

function check(name, fn) {
    try { fn(); console.log(`✅ ${name}`); }
    catch (e) { console.log(`❌ ${name}: ${e.message}`); }
}

// [1/8] Bash syntax check
check('[1/8] Bash syntax', () => {
    const scripts = fs.readdirSync('scripts').filter(f => f.endsWith('.sh'));
    scripts.forEach(s => {
        try { execSync(`bash -n scripts/${s}`, { stdio: 'pipe' }); }
        catch (e) { throw new Error(`scripts/${s}: ${e.stderr?.toString()}`); }
    });
});

// [2/8] CHANGE_ME scan
check('[2/8] CHANGE_ME scan', () => {
    try {
        const result = execSync(`grep -R --line-number --fixed-string "CHANGE_ME" --exclude-dir=docs --exclude-dir=patches --exclude-dir=releases --exclude-dir=node_modules --exclude-dir=.github --exclude-dir=.claude --exclude=.gitlab-ci.yml --exclude=PATCH.diff --exclude=PATCHLOG.md --exclude=TEST_REPORT.md --exclude=ROLLBACK.md --exclude=integrity_gate.sh --exclude="*.example" --exclude=.env --exclude=.gitleaks.toml -- .`, { stdio: 'pipe' });
        throw new Error('Found CHANGE_ME: ' + result.toString().substring(0, 200));
    } catch (e) {
        if (e.status === 1) return; // grep exit 1 = not found = good
        if (e.message.includes('Found CHANGE_ME')) throw e;
    }
});

// [3/8] Workflow JSON validation
check('[3/8] Workflow JSON validation (basic)', () => {
    const wfs = fs.readdirSync('workflows').filter(f => f.endsWith('.json'));
    wfs.forEach(f => {
        const j = JSON.parse(fs.readFileSync(`workflows/${f}`, 'utf8'));
        if (!j.name) throw new Error(`${f}: missing name`);
        if (!Array.isArray(j.nodes)) throw new Error(`${f}: nodes not array`);
        if (typeof j.connections !== 'object' || Array.isArray(j.connections)) throw new Error(`${f}: connections not object`);
        if (j.active !== undefined && j.active !== null && typeof j.active !== 'boolean') throw new Error(`${f}: active not boolean`);
    });
});

// [3/8] Inbound parse nodes check (W1, W2, W3)
['W1_IN_WA.json', 'W2_IN_IG.json', 'W3_IN_MSG.json'].forEach(base => {
    check(`[3/8] Inbound gates (${base})`, () => {
        const fp = `workflows/${base}`;
        if (!fs.existsSync(fp)) throw new Error(`File not found: ${fp}`);
        const j = JSON.parse(fs.readFileSync(fp, 'utf8'));

        const parseNode = j.nodes.find(n => n.name === 'B0 - Parse & Canonicalize');
        if (!parseNode) throw new Error('Missing B0 - Parse & Canonicalize');
        if (!parseNode.parameters?.jsCode?.includes('ALLOW_QUERY_TOKEN')) throw new Error('ALLOW_QUERY_TOKEN gating missing');

        const tokenNode = j.nodes.find(n => n.name === 'B0 - Token OK?');
        if (!tokenNode) throw new Error('Missing B0 - Token OK?');
        const bools = tokenNode.parameters?.conditions?.boolean || [];
        const hasScopeOk = bools.some(b => b.value1 === '={{$json._auth.scopeOk}}');
        if (!hasScopeOk) throw new Error('missing scopeOk enforcement');

        const denyNode = j.nodes.find(n => n.name === 'B0 - Log Deny (DB)');
        if (!denyNode) throw new Error('Missing B0 - Log Deny (DB)');
        if (!denyNode.parameters?.query?.includes('$6')) throw new Error('Log Deny must parameterize event_type');

        if (!j.nodes.find(n => n.name === 'B0 - Contract Valid?')) throw new Error('missing Contract gate');
        if (!j.nodes.find(n => /^RESP - 200/.test(n.name))) throw new Error('missing RESP - 200 node');
        if (!j.nodes.find(n => /^RESP - (400|401)/.test(n.name))) throw new Error('missing RESP - 400/401 node');

        const webhook = j.nodes.find(n => n.name === 'IN - Webhook');
        if (!webhook || webhook.parameters?.responseMode !== 'responseNode') throw new Error('webhook responseMode must be responseNode');
    });
});

// W1 Admin Access Validator
check('[3/8] W1 Admin Access Validator', () => {
    const j = JSON.parse(fs.readFileSync('workflows/W1_IN_WA.json', 'utf8'));
    if (!j.nodes.find(n => n.name === 'B1a - Admin Access Validator (SECURED)')) throw new Error('missing B1a node');
    const mediaConn = j.connections['B1 - Has Media to Fetch?'];
    if (!mediaConn) throw new Error('missing B1 - Has Media to Fetch? connections');
    const routes = mediaConn.main?.flat() || [];
    if (!routes.find(r => r.node === 'B1a - Admin Access Validator (SECURED)')) throw new Error('bypass detected in B1 route');
});

// Tenant isolation check
check('[3/8] Tenant Isolation', () => {
    const wfs = fs.readdirSync('workflows').filter(f => f.endsWith('.json'));
    wfs.forEach(f => {
        const j = JSON.parse(fs.readFileSync(`workflows/${f}`, 'utf8'));
        const strapiNodes = j.nodes.filter(n => n.type === 'n8n-nodes-base.strapi');
        strapiNodes.forEach(n => {
            const filters = n.parameters?.filters;
            if (!filters?.restaurant_id) throw new Error(`${f} [${n.name}]: no restaurant_id filter`);
            const eq = filters.restaurant_id['$eq'];
            if (!eq || !eq.includes('tenant_context')) throw new Error(`${f} [${n.name}]: restaurant_id must use tenant_context`);
        });
    });
});

// [4/8] Schema tests (python) - just check file exists
check('[4/8] Python test scripts exist', () => {
    ['scripts/validate_contracts.py', 'scripts/test_darja_intents.py', 'scripts/test_template_render.py', 'scripts/test_l10n_script_detection.py'].forEach(f => {
        if (!fs.existsSync(f)) throw new Error(`Missing: ${f}`);
    });
});

// [5/8] DB bootstrap ordering
check('[5/8] DB bootstrap ordering', () => {
    const sql = fs.readFileSync('db/bootstrap.sql', 'utf8');
    const ordersLine = sql.split('\n').findIndex(l => l.includes('CREATE TABLE IF NOT EXISTS orders'));
    const outboxLine = sql.split('\n').findIndex(l => l.includes('CREATE TABLE IF NOT EXISTS outbound_messages'));
    if (ordersLine < 0 || outboxLine < 0) throw new Error('could not locate orders/outbound_messages definitions');
    if (ordersLine > outboxLine) throw new Error('orders must be created before outbound_messages');
});

// [6/8] Required files
check('[6/8] Required files', () => {
    const required = [
        'db/migrations/2026-01-22_p1_db_indexes_retention.sql',
        'db/migrations/2026-01-22_p1_event_types_constraints.sql',
        'db/migrations/2026-01-22_p1_arch_002_contract_slo_event_types.sql',
        'db/migrations/2026-01-22_p1_opssecqa_scopes_admin_audit.sql',
        'scripts/backup_postgres.sh', 'scripts/restore_postgres.sh', 'scripts/backup_redis.sh',
        'scripts/test_harness.sh', 'docker/docker-compose.test.yml',
        'infra/gateway/nginx.test.conf', 'docs/BACKUP_RESTORE.md', 'docs/RUNBOOKS.md',
        'tests/fixtures/00_seed_api_clients.sql', 'workflows/W9_ADMIN_PING.json',
        'workflows/W10_CUSTOMER_DELIVERY_QUOTE.json', 'workflows/W11_ADMIN_DELIVERY_ZONES.json',
        'docs/DELIVERY.md', 'templates/delivery/clarify_fr.txt', 'templates/delivery/clarify_ar.txt',
        'templates/delivery/clarify_darja.txt',
        'db/migrations/2026-01-23_p2_epic5_l10n.sql', 'docs/L10N.md', 'docs/ROLLBACK_EPIC5_L10N.md',
        'scripts/test_darja_intents.py', 'scripts/test_template_render.py', 'scripts/test_l10n_script_detection.py',
        'tests/darja_phrases.json',
        'db/migrations/2026-01-22_p2_epic3_tracking.sql', 'workflows/W12_ADMIN_ORDERS.json',
        'docs/TRACKING.md', 'docs/ROLLBACK_EPIC3_TRACKING.md',
        'templates/whatsapp/WA_ORDER_STATUS_templates.fr.json', 'templates/whatsapp/WA_ORDER_STATUS_templates.ar.json',
        'db/migrations/2026-01-23_p2_epic6_support.sql', 'workflows/W14_ADMIN_WA_SUPPORT_CONSOLE.json',
        'docs/SUPPORT.md', 'docs/ROLLBACK_EPIC6_SUPPORT.md',
        'infra/gateway/nginx.conf', 'db/migrations/2026-01-23_p0_sec02_meta_replay.sql',
        'scripts/smoke_security_gateway.sh',
    ];
    const missing = required.filter(f => !fs.existsSync(f));
    if (missing.length > 0) throw new Error(`Missing files:\n  ${missing.join('\n  ')}`);
});

// W8 retention
check('[6/8] W8 Retention Purge', () => {
    const j = JSON.parse(fs.readFileSync('workflows/W8_OPS.json', 'utf8'));
    if (!j.nodes.find(n => n.name === 'R1 - Retention Purge (Daily 03:30)')) throw new Error('missing Retention Purge');
});

// Nginx/L10N in compose
check('[6/8] nginx.conf in prod compose', () => {
    const c = fs.readFileSync('docker-compose.hostinger.prod.yml', 'utf8');
    if (!c.includes('nginx.conf')) throw new Error('nginx.conf not mounted in prod compose');
});

check('[6/8] L10N_ENABLED in prod compose', () => {
    const c = fs.readFileSync('docker-compose.hostinger.prod.yml', 'utf8');
    if (!c.includes('L10N_ENABLED:-true')) throw new Error('L10N_ENABLED not defaulting to true');
});

// [7/8] VERSION check
check('[7/8] VERSION semver', () => {
    const v = fs.readFileSync('VERSION', 'utf8').trim();
    if (!/^\d+\.\d+\.\d+$/.test(v)) throw new Error(`VERSION '${v}' not semver`);
});

// [9/10] Backup scripts lint
check('[9/10] Backup scripts lint', () => {
    const backup = fs.readFileSync('scripts/backup_postgres.sh', 'utf8');
    if (!backup.includes('set -euo pipefail')) throw new Error('backup_postgres.sh missing strict mode');
    const restore = fs.readFileSync('scripts/restore_postgres.sh', 'utf8');
    if (!restore.includes('CONFIRM_RESTORE')) throw new Error('restore_postgres.sh missing CONFIRM_RESTORE gate');
});

// [10/10] P0 Security Config
check('[10/10] P0 Security Config', () => {
    const env = fs.readFileSync('config/.env.example', 'utf8');
    ['LEGACY_SHARED_ALLOWED', 'META_SIGNATURE_REQUIRED', 'STRICT_AR_OUT', 'ADMIN_WA_AUDIT_ENABLED'].forEach(key => {
        if (!env.includes(key)) throw new Error(`.env.example missing ${key}`);
    });
});

console.log('\nDone - see results above');
