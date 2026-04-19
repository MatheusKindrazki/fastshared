// HTML preview page rendered by GET /s/:token when the client sends
// `Accept: text/html`. Pure string construction — no Hono imports, no env
// access. Callers hand in everything needed and we hand back a Response.
//
// BrandPalette hex literals are inlined verbatim. Source of truth lives in
// `apple/Packages/FastSharedCore/Sources/FastSharedCore/BrandPalette.swift` —
// if the brand palette moves, update both places together.

const COLORS = {
  ink: '#12161d',
  nightshade: '#f5f8fb',
  amber: '#00a69c',
  ember: '#4ecf8f',
  coral: '#f0525f',
  dust: '#667085',
  line: '#d7e1e8',
  paper: '#fbfcff',
} as const;

export interface RenderPreviewPageArgs {
  filename: string;
  sizeBytes: number;
  contentType: string;
  expiresAt: Date;
  downloadUrl: string;
  canonicalUrl: string;
  ogImageUrl: string;
  requestNow?: Date;
}

export function renderPreviewPage(args: RenderPreviewPageArgs): Response {
  const now = args.requestNow ?? new Date();
  const msUntilExpiry = Math.max(0, args.expiresAt.getTime() - now.getTime());
  const humanRemaining = humanizeMs(msUntilExpiry);
  const humanSize = formatBytes(args.sizeBytes);

  const safeFilename = escapeHtml(args.filename);
  const safeContentType = escapeHtml(args.contentType);
  const safeSize = escapeHtml(humanSize);
  const safeRemaining = escapeHtml(humanRemaining);
  const safeDownload = escapeHtml(args.downloadUrl);
  const safeCanonical = escapeHtml(args.canonicalUrl);
  const safeOgImage = escapeHtml(args.ogImageUrl);
  const expiresIso = args.expiresAt.toISOString();
  const ogDescription = `Shared via FastShared — expires in ${humanRemaining}`;
  const safeOgDescription = escapeHtml(ogDescription);

  const body = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<meta name="referrer" content="no-referrer" />
<meta name="robots" content="noindex,nofollow" />
<title>${safeFilename}</title>
<link rel="canonical" href="${safeCanonical}" />

<meta property="og:type" content="website" />
<meta property="og:title" content="${safeFilename}" />
<meta property="og:description" content="${safeOgDescription}" />
<meta property="og:image" content="${safeOgImage}" />
<meta property="og:url" content="${safeCanonical}" />
<meta property="og:site_name" content="FastShared" />

<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="${safeFilename}" />
<meta name="twitter:description" content="${safeOgDescription}" />
<meta name="twitter:image" content="${safeOgImage}" />

<style>
  :root {
    --ink: ${COLORS.ink};
    --nightshade: ${COLORS.nightshade};
    --amber: ${COLORS.amber};
    --ember: ${COLORS.ember};
    --coral: ${COLORS.coral};
    --dust: ${COLORS.dust};
    --line: ${COLORS.line};
    --paper: ${COLORS.paper};
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    background: var(--paper);
    color: var(--ink);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    min-height: 100vh;
    display: grid;
    place-items: center;
    padding: 24px;
  }
  main {
    width: 100%;
    max-width: 560px;
    background: #fff;
    border: 1px solid var(--line);
    border-radius: 16px;
    padding: 32px;
    box-shadow: 0 1px 2px rgba(18, 22, 29, 0.04);
  }
  header h1 {
    margin: 0 0 8px;
    font-size: 22px;
    line-height: 1.3;
    word-break: break-word;
  }
  .meta {
    display: flex;
    flex-wrap: wrap;
    gap: 8px 16px;
    font-size: 14px;
    color: var(--dust);
    margin-bottom: 24px;
  }
  .badge {
    display: inline-flex;
    align-items: center;
    padding: 2px 8px;
    border-radius: 999px;
    background: var(--nightshade);
    color: var(--ink);
    font-size: 12px;
    letter-spacing: 0.02em;
  }
  .countdown {
    margin: 24px 0;
    padding: 16px;
    border-radius: 12px;
    background: var(--nightshade);
    border: 1px solid var(--line);
    text-align: center;
  }
  .countdown-label {
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--dust);
    margin-bottom: 6px;
  }
  .countdown-value {
    font-size: 28px;
    font-weight: 600;
    color: var(--amber);
    font-variant-numeric: tabular-nums;
  }
  .countdown-value[data-expired="true"] {
    color: var(--coral);
  }
  .download {
    display: block;
    margin-top: 16px;
    padding: 14px 20px;
    background: var(--amber);
    color: var(--paper);
    border-radius: 10px;
    text-align: center;
    text-decoration: none;
    font-weight: 600;
    font-size: 16px;
  }
  .download:hover, .download:focus { background: var(--ember); }
  footer {
    margin-top: 28px;
    text-align: center;
    font-size: 12px;
    color: var(--dust);
  }
  footer strong { color: var(--ink); }
</style>
</head>
<body>
<main>
  <header>
    <h1>${safeFilename}</h1>
    <div class="meta">
      <span>${safeSize}</span>
      <span class="badge">${safeContentType}</span>
    </div>
  </header>

  <section class="countdown" aria-live="polite">
    <div class="countdown-label">Expires in</div>
    <div class="countdown-value" data-expires-at="${expiresIso}" data-expired="false">${safeRemaining}</div>
  </section>

  <a class="download" href="${safeDownload}" download rel="noopener">Download</a>

  <!-- password-entry form for future release -->

  <footer>
    <strong>FastShared</strong> — share a file, watch it expire.
  </footer>
</main>

<script>
(function () {
  var el = document.querySelector('[data-expires-at]');
  if (!el) return;
  var expiresAt = new Date(el.getAttribute('data-expires-at')).getTime();
  if (!isFinite(expiresAt)) return;
  function pad(n) { return n < 10 ? '0' + n : '' + n; }
  function fmt(ms) {
    if (ms <= 0) return 'expired';
    var s = Math.floor(ms / 1000);
    var d = Math.floor(s / 86400); s -= d * 86400;
    var h = Math.floor(s / 3600); s -= h * 3600;
    var m = Math.floor(s / 60); s -= m * 60;
    if (d > 0) return d + 'd ' + pad(h) + 'h ' + pad(m) + 'm';
    if (h > 0) return pad(h) + 'h ' + pad(m) + 'm ' + pad(s) + 's';
    return pad(m) + 'm ' + pad(s) + 's';
  }
  function tick() {
    var ms = expiresAt - Date.now();
    el.textContent = fmt(ms);
    el.setAttribute('data-expired', ms <= 0 ? 'true' : 'false');
  }
  tick();
  setInterval(tick, 1000);
})();
</script>
</body>
</html>`;

  return new Response(body, {
    status: 200,
    headers: buildHtmlHeaders(),
  });
}

export function renderGonePage(reason: 'expired' | 'revoked' | 'deleted'): Response {
  const titleByReason: Record<'expired' | 'revoked' | 'deleted', string> = {
    expired: 'This link has expired',
    revoked: 'This link was revoked by the sender',
    deleted: 'This file is no longer available',
  };
  const title = titleByReason[reason];
  const safeTitle = escapeHtml(title);
  const safeReason = escapeHtml(reason);

  const body = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<meta name="referrer" content="no-referrer" />
<meta name="robots" content="noindex,nofollow" />
<title>FastShared — ${safeTitle}</title>
<style>
  :root {
    --ink: ${COLORS.ink};
    --paper: ${COLORS.paper};
    --nightshade: ${COLORS.nightshade};
    --coral: ${COLORS.coral};
    --dust: ${COLORS.dust};
    --line: ${COLORS.line};
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    background: var(--paper);
    color: var(--ink);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    min-height: 100vh;
    display: grid;
    place-items: center;
    padding: 24px;
    text-align: center;
  }
  main {
    max-width: 480px;
    padding: 32px;
    border-radius: 16px;
    border: 1px solid var(--line);
    background: #fff;
  }
  h1 { margin: 0 0 8px; font-size: 22px; color: var(--coral); }
  p { margin: 0; color: var(--dust); font-size: 14px; }
  footer { margin-top: 20px; font-size: 12px; color: var(--dust); }
</style>
</head>
<body>
<main>
  <h1>${safeTitle}</h1>
  <p>${safeReason}</p>
  <footer><strong>FastShared</strong></footer>
</main>
</body>
</html>`;

  return new Response(body, {
    status: 410,
    headers: buildHtmlHeaders(),
  });
}

export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return '0 B';
  if (bytes < 1024) return `${bytes} B`;
  const units = ['KB', 'MB', 'GB', 'TB'];
  let value = bytes / 1024;
  let i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  const rounded = value >= 100 ? value.toFixed(0) : value >= 10 ? value.toFixed(1) : value.toFixed(2);
  return `${rounded} ${units[i]}`;
}

function humanizeMs(ms: number): string {
  if (ms <= 0) return 'expired';
  let s = Math.floor(ms / 1000);
  const days = Math.floor(s / 86400);
  s -= days * 86400;
  const hours = Math.floor(s / 3600);
  s -= hours * 3600;
  const minutes = Math.floor(s / 60);
  s -= minutes * 60;
  if (days > 0) return `${days}d ${hours}h ${minutes}m`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  if (minutes > 0) return `${minutes}m ${s}s`;
  return `${s}s`;
}

function buildHtmlHeaders(): Headers {
  const h = new Headers();
  h.set('Content-Type', 'text/html; charset=utf-8');
  h.set(
    'Content-Security-Policy',
    "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'",
  );
  h.set('X-Content-Type-Options', 'nosniff');
  h.set('Referrer-Policy', 'no-referrer');
  h.set('Cache-Control', 'private, no-store');
  h.set('X-Robots-Tag', 'noindex, nofollow');
  return h;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
