// HTML preview page rendered by GET /s/:token when the client sends
// `Accept: text/html`. Pure string construction — no Hono imports, no env
// access. Callers hand in everything needed and we hand back a Response.
//
// Palette tokens come from `web/.impeccable.md` (the locked brand spec).

const COLORS = {
  ink: '#070318',
  nightshade: '#1d0d4b',
  deepViolet: '#3b1f86',
  // `warning` is amber — reserved strictly for urgency signals
  // (expiry countdown, "expiring soon"). Brand/system text now uses violet.
  warning: '#ff9f47',
  ember: '#ffc487',
  coral: '#ff4e7c',
  cream: '#ffe0b8',
  milk: '#fafaff',
  violetHot: '#9d7aff',
  violetSoft: '#c1a9ff',
  violetDust: '#e0d4ff',
  violetFade: '#ff7ad1',
  rule: 'rgba(255,255,255,0.08)',
  ruleSoft: 'rgba(255,255,255,0.04)',
  milkDim: 'rgba(250,250,255,0.56)',
  milkFaint: 'rgba(250,250,255,0.32)',
  milkGhost: 'rgba(250,250,255,0.12)',
} as const;

export interface RenderPreviewPageArgs {
  filename: string;
  sizeBytes: number;
  contentType: string;
  expiresAt: Date;
  downloadUrl: string;
  previewUrl: string;
  canonicalUrl: string;
  ogImageUrl: string;
  textPreview?: string;
  textTruncated?: boolean;
  requestNow?: Date;
}

type PreviewKind = 'image' | 'video' | 'audio' | 'pdf' | 'text' | 'fallback';

function previewKindFor(contentType: string, hasTextPreview: boolean): PreviewKind {
  const ct = contentType.toLowerCase();
  if (ct.startsWith('image/')) return 'image';
  if (ct.startsWith('video/')) return 'video';
  if (ct.startsWith('audio/')) return 'audio';
  if (ct === 'application/pdf') return 'pdf';
  if (
    hasTextPreview &&
    (ct.startsWith('text/') ||
      ct === 'application/json' ||
      ct === 'application/xml' ||
      ct === 'application/javascript' ||
      ct === 'application/yaml')
  ) {
    return 'text';
  }
  return 'fallback';
}

function fileGlyphFor(contentType: string, filename: string): string {
  const ct = contentType.toLowerCase();
  if (ct.startsWith('image/')) return '🖼';
  if (ct.startsWith('video/')) return '🎬';
  if (ct.startsWith('audio/')) return '🎵';
  if (
    ct === 'application/pdf' ||
    ct === 'application/msword' ||
    ct === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
    ct === 'application/vnd.ms-excel' ||
    ct === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
    ct === 'application/vnd.ms-powerpoint' ||
    ct === 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
  ) {
    return '📄';
  }
  if (
    ct === 'application/zip' ||
    ct === 'application/x-tar' ||
    ct === 'application/gzip' ||
    ct === 'application/x-gzip' ||
    ct === 'application/x-rar-compressed' ||
    ct === 'application/vnd.rar' ||
    ct === 'application/x-7z-compressed'
  ) {
    return '📦';
  }
  if (
    ct.startsWith('text/') ||
    ct === 'application/javascript' ||
    ct === 'application/json' ||
    ct === 'application/xml' ||
    ct === 'application/yaml'
  ) {
    return '💾';
  }
  // Filename extension fallback for archives stamped with octet-stream.
  const ext = filename.toLowerCase().match(/\.([a-z0-9]{1,8})$/)?.[1];
  if (ext && ['zip', 'tar', 'gz', 'tgz', 'rar', '7z'].includes(ext)) return '📦';
  return '🔗';
}

export function renderPreviewPage(args: RenderPreviewPageArgs): Response {
  const now = args.requestNow ?? new Date();
  const msUntilExpiry = Math.max(0, args.expiresAt.getTime() - now.getTime());
  const humanRemaining = humanizeMs(msUntilExpiry);
  const humanSize = formatBytes(args.sizeBytes);

  const kind = previewKindFor(args.contentType, typeof args.textPreview === 'string');

  const safeFilename = escapeHtml(args.filename);
  const safeContentType = escapeHtml(args.contentType);
  const safeSize = escapeHtml(humanSize);
  const safeRemaining = escapeHtml(humanRemaining);
  const safeDownload = escapeHtml(args.downloadUrl);
  const safePreview = escapeHtml(args.previewUrl);
  const safeCanonical = escapeHtml(args.canonicalUrl);
  const safeOgImage = escapeHtml(args.ogImageUrl);
  const expiresIso = args.expiresAt.toISOString();
  const ogDescription = `Shared via FastShared — expires in ${humanRemaining}`;
  const safeOgDescription = escapeHtml(ogDescription);

  const viewport = renderViewport(kind, args, safeFilename, safePreview);

  const body = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<meta name="referrer" content="no-referrer" />
<meta name="robots" content="noindex,nofollow" />
<title>${safeFilename}</title>
<link rel="canonical" href="${safeCanonical}" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@600;700&family=JetBrains+Mono:wght@400;600&display=swap" />

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
    --deep-violet: ${COLORS.deepViolet};
    --warning: ${COLORS.warning};
    --coral: ${COLORS.coral};
    --milk: ${COLORS.milk};
    --violet-hot: ${COLORS.violetHot};
    --violet-soft: ${COLORS.violetSoft};
    --rule: ${COLORS.rule};
    --milk-dim: ${COLORS.milkDim};
    --milk-faint: ${COLORS.milkFaint};
    --sans: 'Bricolage Grotesque', system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
    --mono: 'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    background:
      radial-gradient(ellipse at 18% -10%, rgba(157,122,255,0.08) 0%, transparent 50%),
      radial-gradient(ellipse at 92% 18%, rgba(255,122,209,0.06) 0%, transparent 50%),
      var(--ink);
    color: var(--milk);
    font-family: var(--sans);
    min-height: 100vh;
    padding: 24px;
    -webkit-font-smoothing: antialiased;
    text-rendering: optimizeLegibility;
  }
  main {
    width: 100%;
    max-width: 720px;
    margin: 0 auto;
  }
  header {
    margin-bottom: 24px;
  }
  .brand {
    display: inline-block;
    font-size: 22px;
    font-weight: 700;
    letter-spacing: -0.025em;
    color: var(--milk);
    text-decoration: none;
  }
  .brand-dot { color: var(--violet-hot); }
  .viewport {
    border-radius: 20px;
    background: var(--nightshade);
    border: 1px solid var(--rule);
    overflow: hidden;
    min-height: 240px;
    display: grid;
    place-items: center;
  }
  .viewport img {
    display: block;
    max-width: 100%;
    max-height: 70vh;
    width: auto;
    height: auto;
    object-fit: contain;
  }
  .viewport video {
    display: block;
    width: 100%;
    max-height: 70vh;
    background: #000;
  }
  .viewport iframe {
    display: block;
    width: 100%;
    height: 70vh;
    border: none;
    background: #fff;
  }
  .viewport pre {
    margin: 0;
    padding: 24px;
    width: 100%;
    max-height: 60vh;
    overflow: auto;
    font-family: var(--mono);
    font-size: 13px;
    line-height: 1.6;
    color: var(--milk-dim);
    background: var(--nightshade);
    tab-size: 2;
    white-space: pre;
    word-wrap: normal;
  }
  .viewport pre code {
    font-family: inherit;
    color: inherit;
  }
  .text-truncated {
    margin: 0;
    padding: 10px 24px 16px;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--milk-faint);
    background: var(--nightshade);
    text-align: center;
    letter-spacing: 0.04em;
  }
  .glyph-card {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 16px;
    padding: 48px 24px;
    text-align: center;
  }
  .glyph {
    font-size: 80px;
    line-height: 1;
  }
  .glyph-name {
    font-family: var(--mono);
    font-size: 13px;
    color: var(--milk-dim);
    word-break: break-all;
    max-width: 480px;
  }
  .audio-card {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 20px;
    padding: 48px 24px;
    width: 100%;
  }
  .audio-card audio {
    width: 100%;
    max-width: 480px;
  }
  h1 {
    margin: 24px 0 8px;
    font-size: 24px;
    font-weight: 700;
    letter-spacing: -0.025em;
    line-height: 1.25;
    word-break: break-word;
    color: var(--milk);
  }
  .badges {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-items: center;
    color: var(--milk-dim);
    font-size: 14px;
  }
  .badge {
    display: inline-flex;
    align-items: center;
  }
  .badge-mono {
    padding: 4px 10px;
    border-radius: 999px;
    background: rgba(255,255,255,0.06);
    color: var(--milk-dim);
    font-family: var(--mono);
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }
  .countdown {
    margin: 24px 0;
    padding: 18px 20px;
    border-radius: 14px;
    background: var(--nightshade);
    border: 1px solid var(--rule);
    text-align: center;
  }
  .countdown-label {
    font-family: var(--mono);
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: var(--milk-dim);
    margin-bottom: 6px;
  }
  .countdown-value {
    font-family: var(--sans);
    font-size: 32px;
    font-weight: 700;
    letter-spacing: -0.015em;
    color: var(--violet-hot);
    font-variant-numeric: tabular-nums;
    transition: color 250ms cubic-bezier(0.16, 1, 0.3, 1);
  }
  /* Urgent: <1h left — amber warning. Expired: coral. */
  .countdown-value[data-urgent="true"] { color: var(--warning); }
  .countdown-value[data-expired="true"] { color: var(--coral); }
  .download {
    display: block;
    width: 100%;
    padding: 16px 24px;
    background: var(--violet-hot);
    color: var(--ink);
    border-radius: 999px;
    text-align: center;
    text-decoration: none;
    font-family: var(--sans);
    font-weight: 600;
    font-size: 15px;
    letter-spacing: -0.01em;
    transition: filter 120ms ease, transform 120ms ease;
  }
  .download:hover, .download:focus {
    filter: brightness(1.08);
    transform: scale(1.005);
  }
  footer {
    margin-top: 32px;
    text-align: center;
    font-family: var(--mono);
    font-size: 12px;
    color: var(--milk-faint);
  }
  footer a {
    color: var(--milk-dim);
    text-decoration: none;
    border-bottom: 1px dotted var(--milk-faint);
  }
  footer a:hover { color: var(--milk); }
</style>
</head>
<body>
<main>
  <header>
    <a href="https://fastsha.red" class="brand">fastshared<span class="brand-dot">.</span></a>
  </header>

  <section class="viewport">${viewport}</section>

  <section class="meta">
    <h1>${safeFilename}</h1>
    <div class="badges">
      <span class="badge">${safeSize}</span>
      <span class="badge badge-mono">${safeContentType}</span>
    </div>
  </section>

  <section class="countdown" aria-live="polite">
    <div class="countdown-label">Expires in</div>
    <div class="countdown-value" data-expires-at="${expiresIso}" data-expired="false" data-urgent="${msUntilExpiry > 0 && msUntilExpiry < 3_600_000 ? 'true' : 'false'}">${safeRemaining}</div>
  </section>

  <a class="download" href="${safeDownload}" download rel="noopener">Download</a>

  <footer>
    <a href="https://fastsha.red">fastsha.red</a> &middot; share a file, watch it expire.
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
    el.setAttribute('data-urgent', ms > 0 && ms < 3600000 ? 'true' : 'false');
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

function renderViewport(
  kind: PreviewKind,
  args: RenderPreviewPageArgs,
  safeFilename: string,
  safePreview: string,
): string {
  switch (kind) {
    case 'image':
      return `<img src="${safePreview}" alt="${safeFilename}" loading="eager" />`;
    case 'video':
      return `<video controls preload="metadata" src="${safePreview}"></video>`;
    case 'audio':
      return `<div class="audio-card"><div class="glyph">🎵</div><audio controls preload="metadata" src="${safePreview}"></audio></div>`;
    case 'pdf':
      return `<iframe src="${safePreview}" title="PDF preview" loading="eager"></iframe>`;
    case 'text': {
      const safeText = escapeHtml(args.textPreview ?? '');
      const truncatedNote = args.textTruncated
        ? `<div class="text-truncated">truncated &mdash; download to see the rest</div>`
        : '';
      return `<pre><code>${safeText}</code></pre>${truncatedNote}`;
    }
    case 'fallback':
    default: {
      const glyph = fileGlyphFor(args.contentType, args.filename);
      return `<div class="glyph-card"><div class="glyph">${glyph}</div><div class="glyph-name">${safeFilename}</div></div>`;
    }
  }
}

export interface RenderPendingPageArgs {
  filename: string;
  sizeBytes: number;
  expiresAt: Date;
  canonicalUrl: string;
  requestNow?: Date;
}

// Tier 1: served for share_link rows in `pending` state — bytes haven't
// landed in R2 yet. Page auto-refreshes; when the client flips the link to
// `active` via /complete, the next refresh drops into the normal preview.
export function renderPendingPage(args: RenderPendingPageArgs): Response {
  const now = args.requestNow ?? new Date();
  const msUntilExpiry = Math.max(0, args.expiresAt.getTime() - now.getTime());
  const humanRemaining = humanizeMs(msUntilExpiry);

  const safeFilename = escapeHtml(args.filename);
  const safeRemaining = escapeHtml(humanRemaining);
  const safeCanonical = escapeHtml(args.canonicalUrl);

  const body = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<meta name="referrer" content="no-referrer" />
<meta name="robots" content="noindex,nofollow" />
<meta http-equiv="refresh" content="5" />
<title>Uploading — ${safeFilename}</title>
<link rel="canonical" href="${safeCanonical}" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@600;700&family=JetBrains+Mono:wght@400;600&display=swap" />
<style>
  :root {
    --ink: ${COLORS.ink};
    --nightshade: ${COLORS.nightshade};
    --milk: ${COLORS.milk};
    --violet-hot: ${COLORS.violetHot};
    --violet-soft: ${COLORS.violetSoft};
    --rule: ${COLORS.rule};
    --milk-dim: ${COLORS.milkDim};
    --milk-faint: ${COLORS.milkFaint};
    --sans: 'Bricolage Grotesque', system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
    --mono: 'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    background:
      radial-gradient(ellipse at 18% -10%, rgba(157,122,255,0.08) 0%, transparent 50%),
      radial-gradient(ellipse at 92% 18%, rgba(255,122,209,0.06) 0%, transparent 50%),
      var(--ink);
    color: var(--milk);
    font-family: var(--sans);
    min-height: 100vh;
    padding: 24px;
    -webkit-font-smoothing: antialiased;
    text-rendering: optimizeLegibility;
  }
  main {
    width: 100%;
    max-width: 560px;
    margin: 0 auto;
  }
  header { margin-bottom: 48px; }
  .brand {
    display: inline-block;
    font-size: 22px;
    font-weight: 700;
    letter-spacing: -0.025em;
    color: var(--milk);
    text-decoration: none;
  }
  .brand-dot { color: var(--violet-hot); }
  .stage {
    padding: 48px 24px;
    border-radius: 20px;
    background: var(--nightshade);
    border: 1px solid var(--rule);
    text-align: center;
  }
  .ring {
    display: block;
    margin: 0 auto 32px;
    width: 88px;
    height: 88px;
  }
  .ring circle {
    fill: none;
    stroke-width: 4;
    stroke-linecap: round;
  }
  .ring .track { stroke: rgba(255,255,255,0.08); }
  .ring .arc {
    stroke: var(--violet-hot);
    stroke-dasharray: 160 240;
    transform-origin: 50% 50%;
    animation: rotate 1.1s linear infinite;
  }
  @keyframes rotate {
    to { transform: rotate(360deg); }
  }
  @media (prefers-reduced-motion: reduce) {
    .ring .arc { animation: none; stroke-dasharray: 80 320; }
  }
  h1 {
    margin: 0 0 8px;
    font-size: 22px;
    font-weight: 700;
    letter-spacing: -0.025em;
    line-height: 1.25;
    word-break: break-word;
    color: var(--milk);
  }
  .label {
    font-family: var(--mono);
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    color: var(--violet-hot);
    margin-bottom: 20px;
  }
  .hint {
    margin: 24px 0 0;
    font-size: 14px;
    line-height: 1.5;
    color: var(--milk-dim);
  }
  .expiry {
    margin: 12px 0 0;
    font-family: var(--mono);
    font-size: 12px;
    color: var(--milk-faint);
  }
  footer {
    margin-top: 32px;
    text-align: center;
    font-family: var(--mono);
    font-size: 12px;
    color: var(--milk-faint);
  }
  footer a {
    color: var(--milk-dim);
    text-decoration: none;
    border-bottom: 1px dotted var(--milk-faint);
  }
  footer a:hover { color: var(--milk); }
</style>
</head>
<body>
<main>
  <header>
    <a href="https://fastsha.red" class="brand">fastshared<span class="brand-dot">.</span></a>
  </header>
  <section class="stage" aria-live="polite">
    <svg class="ring" viewBox="0 0 44 44" role="img" aria-label="Uploading">
      <circle class="track" cx="22" cy="22" r="18" />
      <circle class="arc" cx="22" cy="22" r="18" />
    </svg>
    <div class="label">Uploading…</div>
    <h1>${safeFilename}</h1>
    <p class="hint">This page refreshes automatically. Come back in a moment.</p>
    <p class="expiry">Expires in ${safeRemaining} once ready.</p>
  </section>
  <footer>
    <a href="https://fastsha.red">fastsha.red</a> &middot; share a file, watch it expire.
  </footer>
</main>
<script>
(function () {
  // Tight poll against /raw — 404 means still pending, 200 means the asset
  // landed. On first 200, reload so the dispatch handler serves the real
  // preview. The meta refresh above is the no-JS fallback.
  var probeUrl = ${JSON.stringify(args.canonicalUrl + '/raw')};
  var timer = setInterval(function () {
    fetch(probeUrl, { method: 'HEAD', cache: 'no-store' }).then(function (r) {
      if (r.status === 200 || r.status === 206) {
        clearInterval(timer);
        location.reload();
      }
    }).catch(function () { /* ignore — meta refresh covers */ });
  }, 3000);
})();
</script>
</body>
</html>`;

  return new Response(body, {
    status: 200,
    headers: buildHtmlHeaders(),
  });
}

// Bundle preview page — N files behind one short link. The page is now an
// editorial gallery: a summary header, a dense responsive grid, and inline
// previews per asset. Download remains per-file so the bundle stays ephemal
// and the browser never needs a ZIP to make the page useful.
export interface BundlePreviewItem {
  assetId: string;
  filename: string;
  sizeBytes: number;
  contentType: string;
  previewUrl: string;
  downloadUrl: string;
}

export interface RenderBundlePreviewPageArgs {
  token: string;
  expiresAt: Date;
  canonicalUrl: string;
  ogImageUrl: string;
  items: BundlePreviewItem[];
  requestNow?: Date;
}

type BundlePreviewKind = 'image' | 'video' | 'audio' | 'pdf' | 'text' | 'fallback';

function bundleMediaKindFor(contentType: string): BundlePreviewKind {
  return previewKindFor(contentType, true);
}

function bundleTypeLabel(kind: BundlePreviewKind): string {
  switch (kind) {
    case 'image':
      return 'Image';
    case 'video':
      return 'Video';
    case 'audio':
      return 'Audio';
    case 'pdf':
      return 'Document';
    case 'text':
      return 'Text';
    default:
      return 'File';
  }
}

// All brand accents are violet-family now; kept per-kind so CSS can distinguish
// cards if we add secondary tints later. Amber is reserved for urgency only.
function bundleAccentFor(kind: BundlePreviewKind): string {
  switch (kind) {
    case 'image':
      return 'violet-hot';
    case 'video':
      return 'violet-hot';
    case 'audio':
      return 'coral';
    case 'pdf':
      return 'violet-soft';
    case 'text':
      return 'milk-dim';
    default:
      return 'violet-dust';
  }
}

function renderBundlePreviewMedia(item: BundlePreviewItem, kind: BundlePreviewKind): string {
  const safePreview = escapeHtml(item.previewUrl);
  const safeFilename = escapeHtml(item.filename);
  switch (kind) {
    case 'image':
      return `<img src="${safePreview}" alt="${safeFilename}" loading="eager" decoding="async" />`;
    case 'video':
      return `<video controls preload="metadata" playsinline src="${safePreview}"></video>`;
    case 'audio':
      return `<div class="preview-empty preview-empty-audio"><strong>Audio</strong><span>${safeFilename}</span><audio controls preload="metadata" src="${safePreview}"></audio></div>`;
    case 'pdf':
      return `<iframe src="${safePreview}" title="${safeFilename}"></iframe>`;
    case 'text':
      return `<iframe src="${safePreview}" title="${safeFilename}"></iframe>`;
    default:
      return `<div class="preview-empty"><strong>${safeFilename}</strong><span>Preview unavailable</span></div>`;
  }
}

function renderBundlePreviewCard(item: BundlePreviewItem, index: number, selected: boolean): string {
  const kind = bundleMediaKindFor(item.contentType);
  const safeFilename = escapeHtml(item.filename);
  const safeSize = escapeHtml(formatBytes(item.sizeBytes));
  const safeType = escapeHtml(bundleTypeLabel(kind));
  const safeIndex = String(index + 1).padStart(2, '0');
  const accent = bundleAccentFor(kind);
  return `<button
  type="button"
  class="file-row${selected ? ' file-row-selected' : ''}"
  data-asset-row
  data-preview-url="${escapeHtml(item.previewUrl)}"
  data-download-url="${escapeHtml(item.downloadUrl)}"
  data-filename="${safeFilename}"
  data-content-type="${escapeHtml(item.contentType)}"
  data-size="${safeSize}"
  data-kind="${safeType}"
  data-kind-accent="${accent}"
  aria-pressed="${selected ? 'true' : 'false'}"
>
  <div class="file-row-index">${safeIndex}</div>
  <div class="file-row-copy">
    <div class="file-row-title" title="${safeFilename}">${safeFilename}</div>
    <div class="file-row-meta">${safeSize} · ${safeType}</div>
  </div>
  <div class="file-row-chevron" aria-hidden="true">›</div>
</button>`;
}

export function renderBundlePreviewPage(args: RenderBundlePreviewPageArgs): Response {
  const now = args.requestNow ?? new Date();
  const msUntilExpiry = Math.max(0, args.expiresAt.getTime() - now.getTime());
  const humanRemaining = humanizeMs(msUntilExpiry);
  const expiresIso = args.expiresAt.toISOString();

  const fileCount = args.items.length;
  const totalBytes = args.items.reduce((sum, item) => sum + item.sizeBytes, 0);
  const typeCounts = args.items.reduce<Record<string, number>>((acc, item) => {
    const kind = bundleMediaKindFor(item.contentType);
    acc[kind] = (acc[kind] ?? 0) + 1;
    return acc;
  }, {});
  const typeSummary = Object.entries(typeCounts)
    .map(([kind, count]) => `${count} ${bundleTypeLabel(kind as BundlePreviewKind).toLowerCase()}${count === 1 ? '' : 's'}`)
    .join(' · ');

  // OG description: enumerate first two filenames + "+N more" trail.
  const previewNames = args.items.slice(0, 2).map((i) => i.filename);
  const remainder = Math.max(0, fileCount - previewNames.length);
  const ogDescription =
    previewNames.length > 0
      ? `${previewNames.join(', ')}${remainder > 0 ? ` +${remainder} more` : ''}`
      : 'Bundle via FastShared';
  const safeOgTitle = escapeHtml(`${fileCount} ${fileCount === 1 ? 'arquivo' : 'arquivos'} via FastShared`);
  const safeOgDescription = escapeHtml(ogDescription);
  const safeCanonical = escapeHtml(args.canonicalUrl);
  const safeOgImage = escapeHtml(args.ogImageUrl);
  const safeRemaining = escapeHtml(humanRemaining);
  const safeTotalBytes = escapeHtml(formatBytes(totalBytes));
  const safeTypeSummary = escapeHtml(typeSummary || 'mixed media');
  const safeHeaderLabel = escapeHtml(`${fileCount} ${fileCount === 1 ? 'arquivo' : 'arquivos'} via FastShared`);
  const selected = args.items[0]!;
  const selectedKind = bundleMediaKindFor(selected.contentType);
  const cards = args.items
    .map((item, index) => renderBundlePreviewCard(item, index, index === 0))
    .join('\n');

  const body = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<meta name="referrer" content="no-referrer" />
<meta name="robots" content="noindex,nofollow" />
<title>${safeHeaderLabel}</title>
<link rel="canonical" href="${safeCanonical}" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@600;700&family=JetBrains+Mono:wght@400;600&display=swap" />

<meta property="og:type" content="website" />
<meta property="og:title" content="${safeOgTitle}" />
<meta property="og:description" content="${safeOgDescription}" />
<meta property="og:image" content="${safeOgImage}" />
<meta property="og:url" content="${safeCanonical}" />
<meta property="og:site_name" content="FastShared" />

<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="${safeOgTitle}" />
<meta name="twitter:description" content="${safeOgDescription}" />
<meta name="twitter:image" content="${safeOgImage}" />

<style>
  :root {
    --ink: ${COLORS.ink};
    --nightshade: ${COLORS.nightshade};
    --panel: rgba(250,250,255,0.04);
    --panel-strong: rgba(250,250,255,0.06);
    --rule: rgba(255,255,255,0.08);
    --rule-soft: rgba(255,255,255,0.05);
    --warning: ${COLORS.warning};
    --coral: ${COLORS.coral};
    --milk: ${COLORS.milk};
    --violet-hot: ${COLORS.violetHot};
    --violet-soft: ${COLORS.violetSoft};
    --violet-dust: ${COLORS.violetDust};
    --milk-dim: ${COLORS.milkDim};
    --milk-faint: ${COLORS.milkFaint};
    --milk-ghost: ${COLORS.milkGhost};
    --sans: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'SF Pro Display', system-ui, sans-serif;
    --mono: 'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; height: 100%; }
  body {
    background:
      radial-gradient(ellipse at 16% 0%, rgba(157,122,255,0.10) 0%, transparent 40%),
      radial-gradient(ellipse at 84% 12%, rgba(255,122,209,0.06) 0%, transparent 36%),
      linear-gradient(180deg, #06020f 0%, #070318 100%);
    color: var(--milk);
    font-family: var(--sans);
    /* lock bundle preview to a single viewport — scroll lives inside .file-list / .viewer-body */
    height: 100vh;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    -webkit-font-smoothing: antialiased;
    text-rendering: optimizeLegibility;
  }
  main {
    position: relative;
    z-index: 1;
    width: 100%;
    max-width: 1440px;
    margin: 0 auto;
    padding: 16px 20px;
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }
  .shell {
    /* fill <main>, keep rhythm: topbar / hero / browser (flex) / expires / footer */
    flex: 1;
    min-height: 0;
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr) auto auto;
    gap: 16px;
  }
  .topbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    padding: 8px 4px 0;
  }
  .brand {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: 18px;
    font-weight: 700;
    letter-spacing: -0.03em;
    color: var(--milk);
    text-decoration: none;
  }
  .brand-dot { color: var(--violet-hot); }
  .bundle-pill {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 9px 12px;
    border-radius: 999px;
    background: rgba(255,255,255,0.05);
    border: 1px solid rgba(255,255,255,0.07);
    color: var(--milk-dim);
    font-family: var(--mono);
    font-size: 11px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  .bundle-pill strong {
    color: var(--milk);
    font-weight: 600;
  }
  .hero {
    display: grid;
    grid-template-columns: minmax(0, 1.25fr) minmax(300px, 0.75fr);
    gap: 16px;
    align-items: stretch;
    flex-shrink: 0;
  }
  .hero-copy, .hero-stats, .browser {
    border: 1px solid var(--rule);
    background: rgba(255,255,255,0.04);
    box-shadow: 0 18px 60px -42px rgba(0,0,0,0.9);
    backdrop-filter: blur(12px);
  }
  .hero-copy {
    border-radius: 24px;
    padding: 18px 20px;
    display: grid;
    gap: 12px;
  }
  .hero-label {
    font-family: var(--mono);
    font-size: 10px;
    color: var(--violet-hot);
    letter-spacing: 0.14em;
    text-transform: uppercase;
  }
  .hero-copy h1 {
    margin: 0;
    font-size: clamp(26px, 3vw, 44px);
    line-height: 1;
    letter-spacing: -0.045em;
  }
  .hero-copy p {
    margin: 0;
    max-width: 62ch;
    color: var(--milk-dim);
    font-size: 15px;
    line-height: 1.55;
  }
  .hero-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .meta-chip {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    padding: 9px 11px;
    border-radius: 999px;
    background: rgba(255,255,255,0.04);
    color: var(--milk-dim);
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    border: 1px solid rgba(255,255,255,0.06);
  }
  .meta-chip strong {
    color: var(--milk);
    font-weight: 600;
  }
  .hero-stats {
    border-radius: 24px;
    padding: 16px;
    display: grid;
    gap: 8px;
    align-content: start;
  }
  .hero-panel {
    display: grid;
    gap: 12px;
  }
  .stat-row {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    padding: 12px 0;
    border-bottom: 1px solid rgba(255,255,255,0.06);
  }
  .stat-row:last-child { border-bottom: 0; }
  .stat-row span {
    color: var(--milk-dim);
    font-family: var(--mono);
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.1em;
  }
  .stat-row strong {
    color: var(--milk);
    font-size: 14px;
    font-weight: 600;
    text-align: right;
  }
  .browser {
    border-radius: 28px;
    /* occupy the 1fr row in .shell grid, clip so inner panes handle scroll */
    min-height: 0;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .window-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    padding: 14px 16px;
    background: rgba(255,255,255,0.03);
    border-bottom: 1px solid var(--rule);
  }
  .traffic {
    display: flex;
    gap: 8px;
  }
  .traffic span {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: rgba(255,255,255,0.18);
  }
  .traffic span:nth-child(1) { background: #ff5f57; }
  .traffic span:nth-child(2) { background: #febc2e; }
  .traffic span:nth-child(3) { background: #28c840; }
  .window-url {
    flex: 1;
    min-width: 0;
    text-align: center;
    font-family: var(--mono);
    font-size: 10px;
    color: var(--milk-faint);
    letter-spacing: 0.08em;
    text-transform: uppercase;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .window-actions {
    display: flex;
    gap: 8px;
    color: var(--milk-faint);
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  .window-actions span {
    padding: 6px 8px;
    border-radius: 999px;
    background: rgba(255,255,255,0.04);
    border: 1px solid rgba(255,255,255,0.05);
  }
  .browser-body {
    display: grid;
    grid-template-columns: 300px minmax(0, 1fr);
    flex: 1;
    min-height: 0;
    overflow: hidden;
  }
  .sidebar {
    display: flex;
    flex-direction: column;
    background: rgba(255,255,255,0.03);
    border-right: 1px solid var(--rule);
    min-height: 0;
    overflow: hidden;
  }
  .sidebar-head {
    padding: 18px 18px 14px;
    border-bottom: 1px solid var(--rule-soft);
    display: grid;
    gap: 10px;
  }
  .sidebar-title {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    font-size: 14px;
    font-weight: 700;
    letter-spacing: -0.02em;
  }
  .sidebar-title small {
    font-family: var(--mono);
    font-size: 10px;
    color: var(--milk-faint);
    text-transform: uppercase;
    letter-spacing: 0.1em;
  }
  .sidebar-sub {
    color: var(--milk-dim);
    font-size: 13px;
    line-height: 1.45;
  }
  .sidebar-meta {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;
  }
  .sidebar-meta .meta-chip {
    justify-content: space-between;
    width: 100%;
  }
  .file-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 14px;
    flex: 1;
    min-height: 0;
    overflow-y: auto;
  }
  .file-row {
    display: grid;
    grid-template-columns: 44px minmax(0, 1fr) auto;
    gap: 12px;
    align-items: center;
    width: 100%;
    padding: 12px 12px;
    border-radius: 18px;
    background: rgba(255,255,255,0.03);
    border: 1px solid transparent;
    color: inherit;
    text-align: left;
    cursor: pointer;
    appearance: none;
    font: inherit;
  }
  .file-row:hover,
  .file-row:focus-visible {
    outline: none;
    border-color: rgba(255,255,255,0.1);
    background: rgba(255,255,255,0.05);
  }
  .file-row-selected {
    background: linear-gradient(180deg, rgba(255,255,255,0.08), rgba(255,255,255,0.04));
    border-color: rgba(255,255,255,0.12);
  }
  .file-row-index {
    width: 44px;
    height: 44px;
    border-radius: 14px;
    display: grid;
    place-items: center;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--asset-accent, var(--violet-soft));
    background: rgba(255,255,255,0.04);
    border: 1px solid rgba(255,255,255,0.05);
  }
  .file-row-title {
    font-size: 14px;
    font-weight: 650;
    letter-spacing: -0.015em;
    line-height: 1.2;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .file-row-meta {
    margin-top: 4px;
    font-family: var(--mono);
    font-size: 10px;
    color: var(--milk-faint);
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  .file-row-chevron {
    color: var(--milk-faint);
    font-size: 20px;
    line-height: 1;
  }
  .viewer {
    display: grid;
    grid-template-rows: auto 1fr auto;
    min-width: 0;
    min-height: 0;
    overflow: hidden;
  }
  .viewer-head {
    padding: 18px 20px;
    display: flex;
    align-items: start;
    justify-content: space-between;
    gap: 16px;
    border-bottom: 1px solid var(--rule-soft);
  }
  .viewer-copy {
    display: grid;
    gap: 6px;
    min-width: 0;
  }
  .viewer-title {
    font-size: clamp(24px, 3vw, 40px);
    line-height: 1.04;
    letter-spacing: -0.05em;
    font-weight: 700;
    word-break: break-word;
  }
  .viewer-sub {
    color: var(--milk-dim);
    font-size: 14px;
    line-height: 1.45;
  }
  .viewer-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    justify-content: flex-end;
  }
  .viewer-action {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 9px 12px;
    border-radius: 999px;
    text-decoration: none;
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    border: 1px solid rgba(255,255,255,0.08);
    background: rgba(255,255,255,0.04);
    color: var(--milk);
  }
  .viewer-action-primary {
    background: var(--asset-accent, var(--violet-hot));
    color: var(--ink);
    border-color: transparent;
  }
  .viewer-body {
    min-height: 0;
    padding: 18px 18px 0;
    overflow: auto;
  }
  .preview-frame {
    height: 100%;
    min-height: 0;
    border-radius: 24px;
    overflow: hidden;
    border: 1px solid var(--rule);
    background: rgba(0,0,0,0.18);
    display: grid;
    place-items: center;
  }
  .preview-frame img,
  .preview-frame video,
  .preview-frame iframe {
    display: block;
    width: 100%;
    height: 100%;
    border: 0;
  }
  .preview-frame img {
    object-fit: contain;
    background: rgba(255,255,255,0.02);
  }
  .preview-frame video {
    background: #000;
  }
  .preview-frame iframe {
    background: #f7f7fb;
  }
  .preview-empty {
    width: 100%;
    min-height: 100%;
    display: grid;
    place-items: center;
    padding: 28px;
    text-align: center;
    color: var(--milk-dim);
  }
  .preview-empty strong {
    color: var(--milk);
    display: block;
    margin-bottom: 8px;
  }
  .viewer-foot {
    display: grid;
    gap: 12px;
    padding: 18px 20px 20px;
    border-top: 1px solid var(--rule-soft);
  }
  .expiry-row {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    align-items: center;
    font-family: var(--mono);
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: var(--milk-faint);
  }
  .expiry-value {
    color: var(--milk);
  }
  .gutter {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    align-items: center;
    font-size: 13px;
    color: var(--milk-dim);
  }
  .gutter strong {
    color: var(--milk);
    font-weight: 650;
  }
  footer {
    margin: 0;
    text-align: center;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--milk-faint);
  }
  footer a {
    color: var(--milk-dim);
    text-decoration: none;
    border-bottom: 1px dotted var(--milk-faint);
  }
  footer a:hover { color: var(--milk); }
  .expires {
    margin: 0 2px;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--milk-faint);
    letter-spacing: 0.04em;
    text-transform: uppercase;
    text-align: right;
  }
  .gallery-marker {
    display: none;
  }
  @media (max-width: 1040px) {
    /* below desktop, go back to natural document scroll — sidebar stacks above viewer */
    html, body { height: auto; }
    body {
      height: auto;
      overflow: auto;
      display: block;
    }
    main {
      height: auto;
      flex: none;
      padding: 16px;
    }
    .shell {
      display: grid;
      grid-template-rows: none;
      flex: none;
    }
    .hero {
      grid-template-columns: 1fr;
    }
    .browser {
      min-height: 0;
      overflow: visible;
      display: block;
    }
    .browser-body {
      grid-template-columns: 1fr;
      min-height: 0;
      overflow: visible;
    }
    .sidebar {
      border-right: 0;
      border-bottom: 1px solid var(--rule);
      overflow: visible;
    }
    .file-list {
      overflow: visible;
      flex: none;
    }
    .viewer {
      overflow: visible;
    }
    .viewer-body {
      padding-bottom: 18px;
      overflow: visible;
    }
    .preview-frame {
      min-height: 420px;
    }
  }
  @media (max-width: 720px) {
    body { padding: 0; }
    main { padding: 12px; }
    .topbar {
      flex-direction: column;
      align-items: flex-start;
    }
    .hero-copy, .hero-stats, .browser {
      border-radius: 22px;
    }
    .sidebar-meta {
      grid-template-columns: 1fr;
    }
    .window-bar {
      padding-inline: 12px;
    }
    .window-actions {
      display: none;
    }
    .viewer-head {
      flex-direction: column;
      align-items: stretch;
    }
    .viewer-actions {
      justify-content: flex-start;
    }
    .file-row {
      grid-template-columns: 40px minmax(0, 1fr) auto;
    }
    .preview-frame {
      min-height: 300px;
    }
  }
</style>
</head>
<body>
<main class="shell">
  <div class="topbar">
    <a href="https://fastsha.red" class="brand">fastshared<span class="brand-dot">.</span></a>
    <div class="bundle-pill"><strong>${safeHeaderLabel}</strong> · native bundle viewer</div>
  </div>

  <section class="hero">
    <div class="hero-copy">
      <div class="hero-label">Bundle preview</div>
      <h1>${safeHeaderLabel}</h1>
      <p>A short link for the whole drop. The layout behaves more like an Apple-style file viewer: files on the left, preview on the right, no noisy web chrome.</p>
      <div class="hero-meta">
        <span class="meta-chip"><strong>${fileCount}</strong> files</span>
        <span class="meta-chip"><strong>${safeTotalBytes}</strong> total</span>
        <span class="meta-chip"><strong>${safeTypeSummary}</strong></span>
      </div>
    </div>
    <aside class="hero-stats" aria-label="Bundle facts">
      <div class="stat-row">
        <span>Lead file</span>
        <strong>${escapeHtml(selected.filename)}</strong>
      </div>
      <div class="stat-row">
        <span>Expires in</span>
        <strong>${safeRemaining}</strong>
      </div>
      <div class="stat-row">
        <span>Media type</span>
        <strong>${escapeHtml(bundleTypeLabel(selectedKind))}</strong>
      </div>
    </aside>
  </section>

  <section class="browser" data-bundle-gallery aria-label="Bundle viewer">
    <div class="window-bar">
      <div class="traffic" aria-hidden="true"><span></span><span></span><span></span></div>
      <div class="window-url">${escapeHtml(args.canonicalUrl)}</div>
      <div class="window-actions" aria-hidden="true"><span>preview</span><span>share</span></div>
    </div>
    <div class="browser-body">
      <aside class="sidebar" aria-label="Files">
        <div class="sidebar-head">
          <div class="sidebar-title">
            <span>Files</span>
            <small>${fileCount}</small>
          </div>
          <div class="sidebar-sub">${safeTypeSummary} · swipe/click to switch the preview</div>
          <div class="sidebar-meta">
            <span class="meta-chip"><strong>${fileCount}</strong> items</span>
            <span class="meta-chip"><strong>${safeRemaining}</strong> left</span>
          </div>
        </div>
        <div class="file-list" role="listbox" aria-label="Bundle files">
          ${cards}
        </div>
      </aside>
      <section class="viewer" aria-label="Selected file preview">
        <div class="viewer-head">
          <div class="viewer-copy">
            <div class="viewer-title" data-viewer-title>${escapeHtml(selected.filename)}</div>
            <div class="viewer-sub" data-viewer-sub>${safeTypeSummary} · ${escapeHtml(formatBytes(selected.sizeBytes))}</div>
          </div>
          <div class="viewer-actions">
            <a class="viewer-action viewer-action-primary" data-viewer-download href="${escapeHtml(selected.downloadUrl)}" download rel="noopener">Download</a>
            <a class="viewer-action" href="${safeCanonical}" rel="noopener">Open link</a>
          </div>
        </div>
        <div class="viewer-body">
          <div class="preview-frame" data-viewer-frame>${renderBundlePreviewMedia(selected, selectedKind)}</div>
        </div>
        <div class="viewer-foot">
          <div class="expiry-row">
            <span>Expires</span>
            <span class="expiry-value" data-expires-at="${expiresIso}" data-expired="false">${safeRemaining}</span>
          </div>
          <div class="gutter">
            <span>${safeTotalBytes} total across ${fileCount} files</span>
            <span>FastShared bundle</span>
          </div>
        </div>
      </section>
    </div>
  </section>

  <div class="expires">expires in ${safeRemaining}</div>

  <footer>
    <a href="https://fastsha.red">fastsha.red</a> &middot; share files, watch them expire.
  </footer>
</main>

<script>
(function () {
  var expiresEl = document.querySelector('[data-expires-at]');
  if (!expiresEl) return;
  var expiresAt = new Date(expiresEl.getAttribute('data-expires-at')).getTime();
  if (!isFinite(expiresAt)) return;
  var titleEl = document.querySelector('[data-viewer-title]');
  var subEl = document.querySelector('[data-viewer-sub]');
  var downloadEl = document.querySelector('[data-viewer-download]');
  var frameEl = document.querySelector('[data-viewer-frame]');
  var rows = Array.from(document.querySelectorAll('[data-asset-row]'));
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
  function mediaMarkup(row) {
    var previewUrl = row.getAttribute('data-preview-url') || '';
    var filename = row.getAttribute('data-filename') || 'download';
    var kind = row.getAttribute('data-kind') || 'File';
    if (kind === 'Image') {
      return '<img src="' + previewUrl + '" alt="' + escapeAttr(filename) + '" loading="eager" decoding="async" />';
    }
    if (kind === 'Video') {
      return '<video controls preload="metadata" playsinline src="' + previewUrl + '"></video>';
    }
    if (kind === 'Audio') {
      return '<div class="preview-empty"><strong>Audio</strong><span>' + escapeHtmlText(filename) + '</span><audio controls preload="metadata" src="' + previewUrl + '"></audio></div>';
    }
    if (kind === 'Document') {
      return '<iframe src="' + previewUrl + '" title="' + escapeAttr(filename) + '"></iframe>';
    }
    if (kind === 'Text') {
      return '<iframe src="' + previewUrl + '" title="' + escapeAttr(filename) + '"></iframe>';
    }
    return '<div class="preview-empty"><strong>' + escapeHtmlText(filename) + '</strong><span>Preview unavailable</span></div>';
  }
  function escapeAttr(s) {
    return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  function escapeHtmlText(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  function selectRow(row) {
    rows.forEach(function (r) {
      var selected = r === row;
      r.classList.toggle('file-row-selected', selected);
      r.setAttribute('aria-pressed', selected ? 'true' : 'false');
    });
    var previewUrl = row.getAttribute('data-preview-url') || '';
    var downloadUrl = row.getAttribute('data-download-url') || '#';
    var filename = row.getAttribute('data-filename') || 'download';
    var size = row.getAttribute('data-size') || '';
    var kind = row.getAttribute('data-kind') || '';
    var accent = row.getAttribute('data-kind-accent') || 'violet-hot';
    if (titleEl) titleEl.textContent = filename;
    if (subEl) subEl.textContent = kind + ' · ' + size;
    if (downloadEl) {
      downloadEl.setAttribute('href', downloadUrl);
      downloadEl.setAttribute('style', '--asset-accent: var(--' + accent + ')');
    }
    if (frameEl) {
      frameEl.innerHTML = mediaMarkup(row);
    }
  }
  function tick() {
    var ms = expiresAt - Date.now();
    var text = fmt(ms);
    expiresEl.textContent = text;
    expiresEl.setAttribute('data-expired', ms <= 0 ? 'true' : 'false');
  }
  function bind(row) {
    row.addEventListener('click', function () {
      selectRow(row);
    });
  }
  rows.forEach(bind);
  if (rows.length > 0) selectRow(rows[0]);
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
  const subtitleByReason: Record<'expired' | 'revoked' | 'deleted', string> = {
    expired: 'The countdown ran out. The file is gone — that\u2019s the point.',
    revoked: 'The sender pulled this share before it expired.',
    deleted: 'The bytes have been wiped from storage.',
  };
  const safeTitle = escapeHtml(titleByReason[reason]);
  const safeSubtitle = escapeHtml(subtitleByReason[reason]);

  const body = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<meta name="referrer" content="no-referrer" />
<meta name="robots" content="noindex,nofollow" />
<title>FastShared — ${safeTitle}</title>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@600;700&family=JetBrains+Mono:wght@400;600&display=swap" />
<style>
  :root {
    --ink: ${COLORS.ink};
    --nightshade: ${COLORS.nightshade};
    --milk: ${COLORS.milk};
    --milk-dim: ${COLORS.milkDim};
    --milk-faint: ${COLORS.milkFaint};
    --coral: ${COLORS.coral};
    --violet-hot: ${COLORS.violetHot};
    --rule: ${COLORS.rule};
    --sans: 'Bricolage Grotesque', system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
    --mono: 'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    background:
      radial-gradient(ellipse at 18% -10%, rgba(157,122,255,0.08) 0%, transparent 50%),
      radial-gradient(ellipse at 92% 18%, rgba(255,122,209,0.06) 0%, transparent 50%),
      var(--ink);
    color: var(--milk);
    font-family: var(--sans);
    min-height: 100vh;
    padding: 24px;
    -webkit-font-smoothing: antialiased;
  }
  main {
    width: 100%;
    max-width: 560px;
    margin: 0 auto;
  }
  header { margin-bottom: 32px; }
  .brand {
    display: inline-block;
    font-size: 22px;
    font-weight: 700;
    letter-spacing: -0.025em;
    color: var(--milk);
    text-decoration: none;
  }
  .brand-dot { color: var(--violet-hot); }
  .card {
    padding: 40px 32px;
    border-radius: 20px;
    background: var(--nightshade);
    border: 1px solid var(--rule);
    text-align: center;
  }
  h1 {
    margin: 0 0 12px;
    font-size: 28px;
    font-weight: 700;
    letter-spacing: -0.025em;
    color: var(--coral);
  }
  p {
    margin: 0;
    color: var(--milk-dim);
    font-size: 15px;
    line-height: 1.5;
  }
  footer {
    margin-top: 32px;
    text-align: center;
    font-family: var(--mono);
    font-size: 12px;
    color: var(--milk-faint);
  }
  footer a {
    color: var(--milk-dim);
    text-decoration: none;
    border-bottom: 1px dotted var(--milk-faint);
  }
  footer a:hover { color: var(--milk); }
</style>
</head>
<body>
<main>
  <header>
    <a href="https://fastsha.red" class="brand">fastshared<span class="brand-dot">.</span></a>
  </header>
  <section class="card">
    <h1>${safeTitle}</h1>
    <p>${safeSubtitle}</p>
  </section>
  <footer>
    <a href="https://fastsha.red">fastsha.red</a> &middot; share a file, watch it expire.
  </footer>
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
    [
      "default-src 'self'",
      "img-src 'self' data:",
      "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
      "script-src 'self' 'unsafe-inline'",
      "font-src 'self' https://fonts.gstatic.com",
      "media-src 'self'",
      "frame-src 'self'",
    ].join('; '),
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
