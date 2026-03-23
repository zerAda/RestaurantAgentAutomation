/**
 * [OBS-02] Structured JSON Logger Configuration
 *
 * Overrides Strapi's default Pino logger to emit structured JSON (NDJSON)
 * in production. Each log entry includes:
 *   - level:      string ("info", "warn", "error", etc.)
 *   - msg:        the log message
 *   - time:       ISO 8601 timestamp
 *   - service:    "strapi-cms" (constant, for log aggregation routing)
 *   - request_id: correlation ID from nginx X-Request-ID header (if present)
 *
 * In development (NODE_ENV !== 'production'), Strapi's default pretty-print
 * transport is preserved so local development remains readable.
 */
import pino from 'pino';
import { requestContextStorage } from '../src/middlewares/request-id.js';

const isProduction = process.env.NODE_ENV === 'production';

export default {
  // Disable the default Strapi pretty-print logger in production
  logger: {
    level: isProduction ? 'info' : 'debug',
    // In production: structured JSON to stdout
    // In development: Strapi's default transport (readable format)
    ...(isProduction
      ? {
          formatters: {
            level(label: string) {
              return { level: label };
            },
            log(object: Record<string, unknown>) {
              const store = requestContextStorage.getStore();
              const requestId = store?.requestId ?? '';
              return requestId
                ? { ...object, request_id: requestId, service: 'strapi-cms' }
                : { ...object, service: 'strapi-cms' };
            },
          },
          timestamp: pino.stdTimeFunctions.isoTime,
          // Suppress Strapi's default pretty transport in production
          transport: undefined,
        }
      : {}),
  },
};
