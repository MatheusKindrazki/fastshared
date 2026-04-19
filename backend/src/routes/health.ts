import { Hono } from 'hono';
import type { AppBindings } from '~/env';

export const healthRoutes = new Hono<AppBindings>();

healthRoutes.get('/', (c) => c.json({ ok: true, version: '0.1.0', now: new Date().toISOString() }));
