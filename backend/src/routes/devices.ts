import { Hono } from 'hono';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { createDevice, hashDeviceToken, updateDevicePushToken } from '~/services/devices';
import { toBase64Url } from '~/lib/hash';
import { ratelimit } from '~/middleware/ratelimit';
import { auth } from '~/middleware/auth';

const registerSchema = z.object({
  platform: z.enum(['ios', 'ipados', 'macos', 'cli']),
  appVersion: z.string().min(1).max(64),
  idfv: z.string().min(1).max(128).optional(),
});

const pushTokenSchema = z.object({
  apnsToken: z
    .string()
    .min(32)
    .max(512)
    .regex(/^[a-fA-F0-9]+$/),
  environment: z.enum(['development', 'production']),
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

deviceRoutes.post('/push-token', auth(), async (c) => {
  const body = pushTokenSchema.parse(await c.req.json());
  const deviceId = c.get('deviceId');
  if (!deviceId) return c.json({ error: 'unauthorized' }, 401);

  const db = createDb(c.env.DATABASE_URL);
  await updateDevicePushToken(db, deviceId, {
    apnsToken: body.apnsToken.toLowerCase(),
    environment: body.environment,
  });

  return c.json({ ok: true });
});
