import type { MiddlewareHandler } from 'hono';
import type { AppBindings } from '~/env';

const HEADER = 'X-Request-ID';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const requestId = (): MiddlewareHandler<AppBindings> => async (c, next) => {
  const inbound = c.req.header(HEADER);
  const id = inbound && UUID_RE.test(inbound) ? inbound : crypto.randomUUID();
  c.set('requestId', id);
  c.set('startedAt', Date.now());
  await next();
  c.res.headers.set(HEADER, id);
};
