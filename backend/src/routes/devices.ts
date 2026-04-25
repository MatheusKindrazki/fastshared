import { Hono } from 'hono';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { createDevice, hashDeviceToken } from '~/services/devices';
import { toBase64Url } from '~/lib/hash';
import { ratelimit } from '~/middleware/ratelimit';

const registerSchema = z.object({
  platform: z.enum(['ios', 'ipados', 'macos', 'cli']),
  appVersion: z.string().min(1).max(64),
  idfv: z.string().min(1).max(128).optional(),
});

export const deviceRoutes = new Hono<AppBindings>();

// Unauthenticated endpoint — rate-limit by IP to blunt registration floods.
deviceRoutes.use(
  '/',
  ratelimit({ bucket: 'device_register', limit: 10, windowSeconds: 600, keyFrom: 'ip' }),
);

deviceRoutes.post('/', async (c) => {
  const body = registerSchema.parse(await c.req.json());

  const tokenBytes = new Uint8Array(32);
  crypto.getRandomValues(tokenBytes);
  const deviceToken = toBase64Url(tokenBytes);
  const tokenHash = await hashDeviceToken(deviceToken, c.env.DEVICE_TOKEN_PEPPER);

  const db = createDb(c.env.DATABASE_URL);
  const device = await createDevice({
    db,
    tokenHash,
    platform: body.platform,
    appVersion: body.appVersion,
  });

  return c.json({ deviceId: device.id, deviceToken }, 201);
});
