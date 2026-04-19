import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { z } from 'zod';
import type { AppBindings } from '~/env';
import { createDb } from '~/db/client';
import { auth } from '~/middleware/auth';
import { softDeleteAsset } from '~/services/assets';

export const assetRoutes = new Hono<AppBindings>();

assetRoutes.use('*', auth());

const paramSchema = z.object({
  assetId: z.string().uuid(),
});

assetRoutes.delete('/:assetId', async (c) => {
  const { assetId } = paramSchema.parse({ assetId: c.req.param('assetId') });
  const deviceId = c.get('deviceId');
  if (!deviceId) throw new HTTPException(401, { message: 'no device' });

  const db = createDb(c.env.DATABASE_URL);
  const ok = await softDeleteAsset(db, assetId, deviceId);
  if (!ok) throw new HTTPException(404, { message: 'asset not found' });

  return c.json({ ok: true });
});
