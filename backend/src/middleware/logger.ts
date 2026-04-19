import type { MiddlewareHandler } from 'hono';
import type { AppBindings } from '~/env';
import { log } from '~/lib/logger';

export const logger = (): MiddlewareHandler<AppBindings> => async (c, next) => {
  const start = c.get('startedAt') ?? Date.now();
  try {
    await next();
  } finally {
    const durationMs = Date.now() - start;
    log.info({
      msg: 'http_request',
      method: c.req.method,
      path: new URL(c.req.url).pathname,
      status: c.res.status,
      durationMs,
      deviceId: c.get('deviceId'),
      requestId: c.get('requestId'),
    });
  }
};
