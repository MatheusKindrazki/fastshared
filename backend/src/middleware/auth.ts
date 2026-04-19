import type { MiddlewareHandler } from 'hono';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { findDeviceByTokenHash, hashDeviceToken, touchLastSeen } from '~/services/devices';
import { problem } from '~/lib/problem';
import { log } from '~/lib/logger';

export const auth = (): MiddlewareHandler<AppBindings> => async (c, next) => {
  const header = c.req.header('authorization') ?? c.req.header('Authorization');
  if (!header || !header.toLowerCase().startsWith('bearer ')) {
    return problem(c, 401, 'unauthorized', 'Unauthorized', 'Missing bearer token');
  }
  const raw = header.slice(7).trim();
  if (raw.length === 0) {
    return problem(c, 401, 'unauthorized', 'Unauthorized', 'Empty bearer token');
  }

  const tokenHash = await hashDeviceToken(raw, c.env.DEVICE_TOKEN_PEPPER);
  const db = createDb(c.env.DATABASE_URL);
  const device = await findDeviceByTokenHash(db, tokenHash);
  if (!device) {
    return problem(c, 401, 'unauthorized', 'Unauthorized', 'Unknown device token');
  }

  c.set('deviceId', device.id);

  // Fire-and-forget last_seen refresh; don't block request on it.
  c.executionCtx.waitUntil(
    touchLastSeen(db, device.id).catch((err) => {
      log.warn({
        msg: 'touch_last_seen_failed',
        requestId: c.get('requestId'),
        deviceId: device.id,
        error: err instanceof Error ? err.message : String(err),
      });
    }),
  );

  await next();
};
