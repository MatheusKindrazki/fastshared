import { Hono } from 'hono';
import type { AppBindings, Env } from '~/env';
import { assertEnv } from '~/env';
import { requestId } from '~/middleware/requestId';
import { cors } from '~/middleware/cors';
import { logger } from '~/middleware/logger';
import { errors } from '~/middleware/errors';
import { healthRoutes } from '~/routes/health';
import { deviceRoutes } from '~/routes/devices';
import { uploadRoutes } from '~/routes/uploads';
import { historyRoutes } from '~/routes/history';
import { assetRoutes } from '~/routes/assets';
import { redirectRoutes } from '~/routes/redirect';
import { revokeRoutes } from '~/routes/revoke';
import { runDueDeletionJobs } from '~/services/deletion';
import { runReconciliation } from '~/services/reconciliation';
import { runMultipartSweeper } from '~/services/multipartSweeper';
import { problem } from '~/lib/problem';
import { log } from '~/lib/logger';

const app = new Hono<AppBindings>();

app.use('*', requestId());
app.use('*', cors());
app.use('*', logger());

// Fail-fast env validation on first request; cheap and gives a clear error
// message rather than cryptic undefined-access blowups deeper in the stack.
let envValidated = false;
app.use('*', async (c, next) => {
  if (!envValidated) {
    try {
      assertEnv(c.env);
      envValidated = true;
    } catch (err) {
      return problem(
        c,
        500,
        'env_misconfigured',
        'Server Misconfigured',
        err instanceof Error ? err.message : String(err),
      );
    }
  }
  await next();
});

app.route('/v1/health', healthRoutes);
app.route('/v1/devices', deviceRoutes);
app.route('/v1/uploads', uploadRoutes);
app.route('/v1/history', historyRoutes);
app.route('/v1/assets', assetRoutes);
app.route('/v1/links', revokeRoutes);
app.route('/s', redirectRoutes);

app.notFound((c) => problem(c, 404, 'not_found', 'Not Found', `no route for ${c.req.path}`));

errors(app);

export default {
  fetch: app.fetch,
  scheduled: async (controller, env, ctx) => {
    try {
      assertEnv(env);
    } catch (err) {
      log.error({
        msg: 'scheduled_env_misconfigured',
        cron: controller.cron,
        error: err instanceof Error ? err.message : String(err),
      });
      return;
    }
    const cron = controller.cron;
    if (cron === '*/1 * * * *') {
      ctx.waitUntil(runDueDeletionJobs(env, ctx));
    } else if (cron === '0 * * * *') {
      ctx.waitUntil(runReconciliation(env));
    } else if (cron === '0 3 * * 0') {
      ctx.waitUntil(runMultipartSweeper(env));
    } else {
      log.warn({ msg: 'scheduled_unknown_cron', cron });
    }
  },
} satisfies ExportedHandler<Env>;
