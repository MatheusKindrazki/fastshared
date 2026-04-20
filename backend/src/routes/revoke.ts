import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { auth } from '~/middleware/auth';
import { ratelimit } from '~/middleware/ratelimit';
import { revokeByToken } from '~/services/shareLinks';
import { scheduleDeletion } from '~/services/assets';
import { log } from '~/lib/logger';

export const revokeRoutes = new Hono<AppBindings>();

revokeRoutes.use('*', auth());
revokeRoutes.use('*', ratelimit({ bucket: 'revoke', limit: 60, windowSeconds: 600 }));

const paramSchema = z.object({ token: z.string().min(1).max(64) });

revokeRoutes.post('/:token/revoke', async (c) => {
  const { token } = paramSchema.parse({ token: c.req.param('token') });
  const deviceId = c.get('deviceId');
  if (!deviceId) throw new HTTPException(401, { message: 'no device on request' });

  const db = createDb(c.env.DATABASE_URL);
  const result = await revokeByToken(db, token, deviceId);
  if (result.status === 'not_found') {
    throw new HTTPException(404, { message: 'share link not found' });
  }
  if (result.status === 'forbidden') {
    throw new HTTPException(403, { message: 'share link does not belong to device' });
  }

  const link = result.link;
  if (!link) throw new Error('revokeByToken returned ok without link');

  // Fast-path: collapse the grace window — the user explicitly asked us to
  // forget this. scheduleDeletion is idempotent via the partial unique index.
  // Pending links have no asset yet so there's nothing to deletion-schedule.
  if (link.assetId) {
    const assetIdForDeletion = link.assetId;
    c.executionCtx.waitUntil(
      scheduleDeletion(db, assetIdForDeletion, new Date()).catch((err) => {
        log.warn({
          msg: 'revoke_schedule_deletion_failed',
          token,
          assetId: assetIdForDeletion,
          error: err instanceof Error ? err.message : String(err),
        });
      }),
    );
  }

  return c.json({
    ok: true,
    linkStatus: link.linkStatus,
    revokedAt: link.revokedAt ? link.revokedAt.toISOString() : new Date().toISOString(),
  });
});
