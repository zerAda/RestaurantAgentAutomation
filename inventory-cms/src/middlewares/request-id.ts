/**
 * [OBS-04] Request ID Middleware
 *
 * Reads the X-Request-ID header injected by the nginx gateway and stores
 * it in an AsyncLocalStorage store so the Pino logger can include it in
 * every log entry emitted during this request's lifecycle — even from
 * service/controller code that does not have ctx access.
 *
 * If no X-Request-ID header is present (e.g. direct CMS access bypassing
 * the gateway), a fallback empty string is stored so log entries remain
 * structurally consistent.
 */
import { AsyncLocalStorage } from 'node:async_hooks';

export interface RequestContext {
  requestId: string;
}

export const requestContextStorage = new AsyncLocalStorage<RequestContext>();

export default (_config: unknown, _ctx: unknown) => {
  return async (ctx: any, next: () => Promise<void>) => {
    const requestId = ctx.get('x-request-id') || '';
    await requestContextStorage.run({ requestId }, next);
  };
};
