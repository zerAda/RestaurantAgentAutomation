const fs = require('fs');
const path = require('path');

const apis = ['cart', 'conversation-state', 'delivery-zone', 'voice-interaction', 'quarantine', 'workflow-error', 'inbound-message'];

apis.forEach(api => {
    const basePath = path.join(__dirname, 'src', 'api', api);

    // Create directories
    ['content-types/' + api, 'controllers', 'routes', 'services'].forEach(dir => {
        fs.mkdirSync(path.join(basePath, dir), { recursive: true });
    });

    // Create schema.json
    const schema = {
        kind: 'collectionType',
        collectionName: api.replace(/-/g, '_') + 's',
        info: {
            singularName: api,
            pluralName: api + 's',
            displayName: api.split('-').map(w => w[0].toUpperCase() + w.slice(1)).join(' ')
        },
        options: {
            draftAndPublish: false
        },
        attributes: {}
    };

    if (api === 'cart') {
        schema.attributes = {
            conversation_key: { type: 'string', required: true, unique: true },
            cart_json: { type: 'json' },
            restaurant_id: { type: 'string', required: true }
        };
    } else if (api === 'conversation-state') {
        schema.attributes = {
            conversation_key: { type: 'string', required: true, unique: true },
            tenant_id: { type: 'string' },
            restaurant_id: { type: 'string' },
            channel: { type: 'enumeration', enum: ['whatsapp', 'instagram', 'messenger'] },
            user_id: { type: 'string' },
            state_json: { type: 'json' }
        };
    } else if (api === 'delivery-zone') {
        schema.attributes = {
            name: { type: 'string', required: true },
            polygon_kml: { type: 'text' },
            active: { type: 'boolean', default: true },
            price_cents: { type: 'integer', default: 0 }
        };
    } else if (api === 'voice-interaction') {
        schema.attributes = {
            conversation_key: { type: 'string' },
            audio_url: { type: 'string' },
            transcript: { type: 'text' },
            confidence: { type: 'decimal' }
        };
    } else if (api === 'quarantine') {
        schema.attributes = {
            conversation_key: { type: 'string', required: true },
            reason: { type: 'text' },
            active: { type: 'boolean', default: true },
            expires_at: { type: 'datetime' }
        };
    } else if (api === 'workflow-error') {
        schema.attributes = {
            workflow_name: { type: 'string' },
            node_name: { type: 'string' },
            error_message: { type: 'text' },
            stack: { type: 'text' },
            execution_id: { type: 'string' }
        };
    } else if (api === 'inbound-message') {
        schema.attributes = {
            conversation_key: { type: 'string', required: true },
            msg_id: { type: 'string', required: true },
            channel: { type: 'string' },
            message_type: { type: 'string' },
            meta_json: { type: 'json' }
        };
    }

    fs.writeFileSync(path.join(basePath, 'content-types', api, 'schema.json'), JSON.stringify(schema, null, 2));

    // Create Controller
    const cnt = `/**
 * ${api} controller
 */
import { factories } from '@strapi/strapi';
export default factories.createCoreController('api::${api}.${api}');
`;
    fs.writeFileSync(path.join(basePath, 'controllers', api + '.ts'), cnt);

    // Create Service
    const svc = `/**
 * ${api} service
 */
import { factories } from '@strapi/strapi';
export default factories.createCoreService('api::${api}.${api}');
`;
    fs.writeFileSync(path.join(basePath, 'services', api + '.ts'), svc);

    // Create Route
    const rte = `/**
 * ${api} router
 */
import { factories } from '@strapi/strapi';
export default factories.createCoreRouter('api::${api}.${api}');
`;
    fs.writeFileSync(path.join(basePath, 'routes', api + '.ts'), rte);

    console.log('Created Strapi API:', api);
});
