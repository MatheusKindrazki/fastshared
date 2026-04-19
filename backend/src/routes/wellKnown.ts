import { Hono } from 'hono';
import type { AppBindings } from '~/env';

// WHY: hardcoded rather than env-driven. The Apple Team ID and Bundle ID are
// tied to the shipped app binary — changing them requires a new app submission,
// so embedding here is simpler than threading a secret that can never differ
// from the checked-in apple/Config/Shared.xcconfig value (YFYB6NKC73) and
// apple/project.yml (dev.kindrazki.fastshared). If we ever fork these MUST be
// kept in lockstep with the client.
const APP_ID = 'YFYB6NKC73.dev.kindrazki.fastshared';

// WHY: the paths array uses Apple's legacy format (NOT the newer `components`
// array with query/fragment support) because we only need whitelist-style
// matching on the short-link namespace `/s/*` and a blacklist on `/api/*` so
// iOS does not try to handoff API traffic to the app. The legacy `paths` keys
// are still fully supported by all our deployment targets (iOS 17+, macOS 14+).
// Reference: https://developer.apple.com/documentation/xcode/supporting-associated-domains
const AASA_BODY = {
  applinks: {
    apps: [],
    details: [
      {
        appID: APP_ID,
        paths: ['/s/*', 'NOT /api/*'],
      },
    ],
  },
} as const;

export const wellKnownRoutes = new Hono<AppBindings>();

// The AASA endpoint MUST be reachable at exactly /.well-known/apple-app-site-association
// with no .json extension and a `Content-Type: application/json` header — Apple's
// CDN refuses anything else. No authentication, no redirects, and the body must
// be served over HTTPS (Cloudflare's edge handles that automatically for the
// custom_domain routes this worker is bound to). We allow caching for 1 hour —
// long enough to reduce chatter during link-preview storms, short enough that
// ops can roll out a paths change the same day.
wellKnownRoutes.get('/apple-app-site-association', (c) => {
  return new Response(JSON.stringify(AASA_BODY), {
    status: 200,
    headers: {
      'content-type': 'application/json',
      'cache-control': 'public, max-age=3600',
    },
  });
});
