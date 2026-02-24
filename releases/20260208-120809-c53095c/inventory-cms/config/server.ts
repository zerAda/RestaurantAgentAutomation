export default ({ env }: { env: any }) => ({
  host: env('HOST', '0.0.0.0'),
  port: env.int('PORT', 1337),
  url: env('STRAPI_URL', 'https://cms.srv1258231.hstgr.cloud'),
  app: {
    keys: env.array('APP_KEYS'),
  },
});
