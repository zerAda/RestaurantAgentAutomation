const { createStrapi } = require('@strapi/strapi');

async function main() {
    console.log('Initializing Strapi...');
    // Point to dist because we built the TS project
    const strapi = createStrapi({ distDir: './dist' });
    await strapi.load();

    const service = strapi.admin.services['api-token'];
    const tokenName = 'n8n-access';

    const exists = await service.exists({ name: tokenName });
    if (exists) {
        console.log(`Token "${tokenName}" already exists.`);
        // We can't retrieve the plain text key again. 
        // If needed, delete and recreate, but for now just warn.
    } else {
        const token = await service.create({
            name: tokenName,
            type: 'full-access',
            description: 'Token for n8n automation',
            lifespan: null,
        });
        console.log('----------------------------------------');
        console.log('N8N_API_TOKEN:', token.accessKey);
        console.log('----------------------------------------');
    }

    // Stop strapi
    await strapi.destroy();
    process.exit(0);
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
