export default ({ env }: { env: any }) => [
  'strapi::logger',
  'strapi::errors',
  {
    name: 'strapi::security',
    config: {
      contentSecurityPolicy: {
        useDefaults: true,
        directives: {
          'default-src': ["'self'"],
          'script-src': ["'self'", "'unsafe-inline'"],
          'style-src': ["'self'", "'unsafe-inline'"],
          'img-src': ["'self'", 'data:', 'blob:', 'https://market-assets.strapi.io'],
          'media-src': ["'self'", 'data:', 'blob:'],
          'connect-src': ["'self'", 'https:'],
          'font-src': ["'self'"],
          'frame-src': ["'none'"],
          'object-src': ["'none'"],
          'base-uri': ["'self'"],
          'form-action': ["'self'"],
          'frame-ancestors': ["'none'"],
          upgradeInsecureRequests: null,
        },
      },
      frameguard: { action: 'deny' },
      hsts: {
        maxAge: 31536000,
        includeSubDomains: true,
        preload: true,
      },
      referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
      crossOriginEmbedderPolicy: false,
      crossOriginOpenerPolicy: { policy: 'same-origin' },
      // BUG-006 FIX: Changed from 'same-origin' to 'cross-origin' so that
      // the Kiosk App on kiosk.* can load images served by cms.*.
      // This is safe because Strapi public endpoints are read-only and
      // the full CORS allowlist above still restricts API access.
      crossOriginResourcePolicy: { policy: 'cross-origin' },
      permittedCrossDomainPolicies: { permittedPolicies: 'none' },
    },
  },
  {
    name: 'strapi::cors',
    config: {
      // BUG-006 FIX: Include all known frontend subdomains in default CORS origins.
      // Previously the default was localhost only, causing cross-origin image blocks.
      origin: env.array('CORS_ORIGINS', [
        'http://localhost:3000',
        'http://localhost:5173',
        `https://kiosk.${env('VPS_HOSTNAME', 'srv1258231.hstgr.cloud')}`,
        `https://admin.${env('VPS_HOSTNAME', 'srv1258231.hstgr.cloud')}`,
      ]),
      methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
      headers: ['Content-Type', 'Authorization', 'Origin', 'Accept'],
      keepHeaderOnError: true,
    },
  },
  {
    name: 'strapi::poweredBy',
    config: {
      poweredBy: 'Strapi',
    },
  },
  'strapi::query',
  {
    name: 'strapi::body',
    config: {
      formLimit: '1mb',
      jsonLimit: '1mb',
      textLimit: '1mb',
      formidable: {
        maxFileSize: 10 * 1024 * 1024, // 10MB
      },
    },
  },
  'strapi::session',
  'strapi::favicon',
  'strapi::public',
  'global::auth-ratelimit',
  'global::prometheus-tracker',
  'global::admin-cookie-auth',
];
