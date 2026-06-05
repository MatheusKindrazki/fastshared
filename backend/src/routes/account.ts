import { Hono } from 'hono';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { auth } from '~/middleware/auth';
import { ratelimit } from '~/middleware/ratelimit';
import { problem } from '~/lib/problem';
import { deleteAccountForDevice } from '~/services/accountDeletion';
import { log } from '~/lib/logger';

export const accountRoutes = new Hono<AppBindings>();

accountRoutes.use('/', auth());
// Deliberately tight: account deletion is irreversible and account-wide, so a
// handful of attempts per 10 minutes is plenty for a legitimate retry.
accountRoutes.use('/', ratelimit({ bucket: 'account_delete', limit: 5, windowSeconds: 600 }));

// DELETE /v1/account — App Store Guideline 5.1.1(v). Removes the whole Apple
// account behind the calling device: deletes the user, unlinks all its devices,
// drops its subscriptions, revokes its active share links, and schedules
// immediate deletion of every asset it owns.
accountRoutes.delete('/', async (c) => {
  const deviceId = c.get('deviceId');
  if (!deviceId) return problem(c, 401, 'unauthorized', 'Unauthorized', 'no device');

  const db = createDb(c.env.DATABASE_URL);
  const result = await deleteAccountForDevice(db, deviceId);

  if (result.status === 'device_not_found') {
    return problem(c, 401, 'unauthorized', 'Unauthorized', 'device no longer exists');
  }
  if (result.status === 'not_linked') {
    return problem(
      c,
      400,
      'not_linked',
      'Account Not Linked',
      'Account is not linked to an Apple ID',
    );
  }

  log.info({
    msg: 'account_deleted',
    requestId: c.get('requestId'),
    userId: result.userId,
    assetsScheduled: result.assetsScheduled,
    linksRevoked: result.linksRevoked,
    devicesUnlinked: result.devicesUnlinked,
  });

  return c.json({
    ok: true,
    assetsScheduled: result.assetsScheduled,
    linksRevoked: result.linksRevoked,
    devicesUnlinked: result.devicesUnlinked,
  });
});
