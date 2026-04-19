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
import { wellKnownRoutes } from '~/routes/wellKnown';
import { assetsPublicRoutes } from '~/routes/assetsPublic';
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
app.route('/.well-known', wellKnownRoutes);
app.route('/', assetsPublicRoutes);

app.notFound((c) => problem(c, 404, 'not_found', 'Not Found', `no route for ${c.req.path}`));

errors(app);

// WHY: the apex fastsha.red serves two concerns on one hostname — the /s/:token
// short-link resolver (always handled by this Worker) and the marketing landing
// page (hosted on Cloudflare Pages at fastshared-web.pages.dev). We proxy any
// non-app path on the apex through to Pages so a single Worker custom_domain
// keeps working without needing a separate Pages custom-domain binding in the
// CF dashboard. api.fastsha.red is unaffected — everything there is /v1/*.
const PAGES_ORIGIN = 'https://fastshared-web.pages.dev';
// /.well-known MUST stay on the worker so iOS/macOS can fetch the AASA file
// directly — if we proxied it to Pages, Apple's CDN would see a 404 HTML body
// and the universal-link handoff would silently never install.
const APP_PATH_PREFIXES = [
  '/s',
  '/s/',
  '/v1',
  '/v1/',
  '/.well-known',
  '/.well-known/',
  '/og-image.png',
];

function isAppPath(pathname: string): boolean {
  return APP_PATH_PREFIXES.some((p) => pathname === p || pathname.startsWith(p + '/') || pathname.startsWith(p));
}

async function routeRequest(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const url = new URL(req.url);
  if (url.hostname === 'fastsha.red' && !isAppPath(url.pathname)) {
    const target = new URL(url.pathname + url.search, PAGES_ORIGIN);
    const proxied = new Request(target.toString(), req);
    const res = await fetch(proxied);
    // Strip any CF-Pages headers that leak the origin hostname to the client.
    const headers = new Headers(res.headers);
    headers.delete('cf-ray');
    headers.delete('server');
    return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
  }
  return app.fetch(req, env, ctx);
}

export default {
  fetch: routeRequest,
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
