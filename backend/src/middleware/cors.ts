import { cors as honoCors } from 'hono/cors';
import type { MiddlewareHandler } from 'hono';
import type { AppBindings } from '~/env';

const ALLOWED = new Set(['https://fastsha.red', 'https://fsh.dev']);

export const cors = (): MiddlewareHandler<AppBindings> =>
  honoCors({
    origin: (origin) => {
      // Apple native clients typically send Origin: null — mirror it.
      if (!origin || origin === 'null') return 'null';
      if (ALLOWED.has(origin)) return origin;
      return null;
    },
    allowHeaders: ['Authorization', 'Content-Type', 'X-Request-ID'],
    allowMethods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
    exposeHeaders: ['X-Request-ID'],
    maxAge: 600,
    credentials: false,
  });
