import { Hono } from 'hono';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { auth } from '~/middleware/auth';
import { ratelimit } from '~/middleware/ratelimit';
import { problem } from '~/lib/problem';
import { log } from '~/lib/logger';
import { findDeviceById, linkDeviceToUser } from '~/services/devices';
import { claimLinkCode, createLinkCode } from '~/services/deviceLinks';

export const linkCodeRoutes = new Hono<AppBindings>();

const claimSchema = z.object({ code: z.string().regex(/^\d{6}$/) });

// An app device that is signed in shows a code to pair a CLI or the web.
linkCodeRoutes.post(
  '/',
  auth(),
  ratelimit({ bucket: 'link_code_create', limit: 10, windowSeconds: 3600 }),
  async (c) => {
    const db = createDb(c.env.DATABASE_URL);
    const current = await findDeviceById(db, c.get('deviceId')!);
    if (!current?.userId) {
      return problem(
        c,
        409,
        'sign_in_required',
        'Sign In Required',
        'sign in on this device before linking another one',
      );
    }
    const { code, expiresAt } = await createLinkCode(db, c.env.DEVICE_TOKEN_PEPPER, {
      userId: current.userId,
      deviceId: current.id,
    });
    return c.json({ code, expiresAt: expiresAt.toISOString() }, 201);
  },
);

// A CLI or web device redeems the code and joins that account. Six digits are
// only safe behind tight limits, so both the device and the IP are throttled.
linkCodeRoutes.post(
  '/claim',
  auth(),
  ratelimit({ bucket: 'link_code_claim_ip', limit: 20, windowSeconds: 3600, keyFrom: 'ip' }),
  ratelimit({ bucket: 'link_code_claim_device', limit: 5, windowSeconds: 600 }),
  async (c) => {
    const parsed = claimSchema.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) {
      return problem(c, 400, 'invalid_code', 'Bad Request', 'the code is six digits');
    }
    const db = createDb(c.env.DATABASE_URL);
    const deviceId = c.get('deviceId')!;
    const current = await findDeviceById(db, deviceId);
    if (!current) return problem(c, 401, 'unauthorized', 'Unauthorized', 'unknown device');
    const userId = await claimLinkCode(db, c.env.DEVICE_TOKEN_PEPPER, {
      code: parsed.data.code,
      deviceId,
    });
    if (!userId) {
      return problem(c, 400, 'invalid_code', 'Bad Request', 'the code is invalid or expired');
    }
    if (current.userId && current.userId !== userId) {
      return problem(
        c,
        409,
        'already_linked',
        'Conflict',
        'this device already belongs to another account',
      );
    }
    await linkDeviceToUser(db, deviceId, userId);
    log.info({ msg: 'device_linked', deviceId, platform: current.platform });
    return c.json({ linked: true, userId });
  },
);
