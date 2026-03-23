/**
 * [OBS-02] Structured JSON Logger Configuration
 *
 * Overrides Strapi's default Winston logger to emit structured JSON (NDJSON)
 * in production. Each log entry includes:
 *   - level:      string ("info", "warn", "error", etc.)
 *   - message:    the log message
 *   - timestamp:  ISO 8601 timestamp
 *   - service:    "strapi-cms" (constant, for log aggregation routing)
 *   - request_id: correlation ID from nginx X-Request-ID header (if present)
 *
 * Strapi 5 uses @strapi/logger (Winston-based). The config/logger.ts export
 * is merged into the Winston configuration via Object.assign. In production,
 * we override the default prettyPrint format with winston.format.json().
 *
 * In development (NODE_ENV !== 'production'), Strapi's default pretty-print
 * transport is preserved so local development remains readable.
 */
import { requestContextStorage } from '../src/middlewares/request-id.js';
import { format } from 'winston';

const isProduction = process.env.NODE_ENV === 'production';

export default isProduction ? {
  level: 'info',
  format: format.combine(
    format.timestamp(),
    format((info) => {
      const store = requestContextStorage.getStore();
      return {
        ...info,
        service: 'strapi-cms',
        request_id: store?.requestId ?? '',
      };
    })(),
    format.json(),
  ),
} : {};
