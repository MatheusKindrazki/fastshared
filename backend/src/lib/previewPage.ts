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
  const glyph = fileGlyphFor(item.contentType, item.filename);
  const accent = bundleAccentFor(kind);
  return `<button
  type="button"
  class="file-row${selected ? ' file-row-selected' : ''}"
  data-asset-row
  data-asset-index="${index}"
  data-preview-url="${escapeHtml(item.previewUrl)}"
  data-download-url="${escapeHtml(item.downloadUrl)}"
  data-filename="${safeFilename}"
  data-content-type="${escapeHtml(item.contentType)}"
  data-size="${safeSize}"
  data-kind="${safeType}"
  data-kind-accent="${accent}"
  aria-pressed="${selected ? 'true' : 'false'}"
>
  <div class="file-row-icon" aria-hidden="true">${glyph}</div>
  <div class="file-row-title" title="${safeFilename}">${safeFilename}</div>
  <div class="file-row-size">${safeSize}</div>
  <div class="file-row-type">${safeType}</div>
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
    /* fill <main>: finder-bar (fixed) / browser (flex) / footer */
    flex: 1;
    min-height: 0;
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr) auto auto;
    gap: 12px;
  }
  .topbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    padding: 4px 4px 0;
  }
  .brand {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: 16px;
    font-weight: 700;
    letter-spacing: -0.03em;
    color: var(--milk);
    text-decoration: none;
  }
  .brand-dot { color: var(--violet-hot); }
  .finder-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 8px 14px;
    border: 1px solid var(--rule);
    border-bottom: 0;
    border-radius: 14px 14px 0 0;
    background: rgba(20, 10, 40, 0.35);
    backdrop-filter: blur(20px);
    flex-shrink: 0;
    height: 44px;
  }
  .finder-title {
    font-size: 13px;
    color: var(--milk);
    font-weight: 500;
    letter-spacing: -0.01em;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .finder-title strong {
    font-weight: 600;
  }
  .finder-title .finder-title-sep {
    margin: 0 6px;
    color: var(--milk-faint);
  }
  .finder-actions { display: flex; gap: 6px; }
  .finder-btn {
    font-size: 12px;
    color: var(--milk-dim);
    padding: 6px 10px;
    border-radius: 8px;
    background: transparent;
    border: 1px solid transparent;
    cursor: pointer;
    text-decoration: none;
    transition: color 0.15s, background 0.15s, border-color 0.15s;
    font-family: var(--sans);
  }
  .finder-btn:hover {
    color: var(--violet-hot);
    background: rgba(157, 122, 255, 0.08);
    border-color: rgba(157, 122, 255, 0.2);
  }
  .browser {
    border: 1px solid var(--rule);
    background: rgba(255,255,255,0.03);
    box-shadow: 0 18px 60px -42px rgba(0,0,0,0.9);
    backdrop-filter: blur(12px);
  }
  .meta-chip {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    padding: 6px 9px;
    border-radius: 999px;
    background: rgba(255,255,255,0.04);
    color: var(--milk-dim);
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    border: 1px solid rgba(255,255,255,0.06);
  }
  .meta-chip strong {
    color: var(--milk);
    font-weight: 600;
  }
  .browser {
    border-radius: 0 0 14px 14px;
    border-top: 0;
    /* occupy the 1fr row in .shell grid, clip so inner panes handle scroll */
    min-height: 0;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .browser-body {
    display: grid;
    grid-template-columns: minmax(320px, 1.1fr) minmax(0, 1fr);
    flex: 1;
    min-height: 0;
    overflow: hidden;
  }
  .sidebar {
    display: flex;
    flex-direction: column;
    background: rgba(20, 10, 40, 0.25);
    border-right: 1px solid var(--rule);
    min-height: 0;
    overflow: hidden;
  }
  .file-list-header {
    display: grid;
    grid-template-columns: 20px minmax(0, 1fr) 90px 70px;
    gap: 12px;
    padding: 8px 14px;
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--milk-faint);
    border-bottom: 1px solid var(--rule-soft);
    flex-shrink: 0;
  }
  .file-list-header .hdr-size,
  .file-list-header .hdr-type { text-align: right; }
  .file-list {
    display: flex;
    flex-direction: column;
    padding: 0;
    flex: 1;
    min-height: 0;
    overflow-y: auto;
  }
  .file-row {
    display: grid;
    grid-template-columns: 20px minmax(0, 1fr) 90px 70px;
    gap: 12px;
    align-items: center;
    width: 100%;
    padding: 6px 14px;
    background: transparent;
    border: 0;
    border-bottom: 1px solid rgba(255, 255, 255, 0.04);
    color: var(--milk-dim);
    text-align: left;
    cursor: pointer;
    appearance: none;
    font: inherit;
    font-size: 13px;
  }
  .file-row:hover {
    background: rgba(157, 122, 255, 0.06);
    color: var(--milk);
  }
  .file-row:focus-visible {
    outline: none;
    background: rgba(157, 122, 255, 0.1);
  }
  .file-row-selected,
  .file-row-selected:hover {
    background: rgba(157, 122, 255, 0.18);
    color: var(--milk);
  }
  .file-row-icon {
    font-size: 15px;
    line-height: 1;
    opacity: 0.85;
    text-align: center;
  }
  .file-row-title {
    font-weight: 500;
    color: var(--milk);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    letter-spacing: -0.005em;
  }
  .file-row-selected .file-row-title { color: var(--milk); }
  .file-row-size,
  .file-row-type {
    text-align: right;
    font-variant-numeric: tabular-nums;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--milk-faint);
  }
  .file-row-selected .file-row-size,
  .file-row-selected .file-row-type { color: var(--milk-dim); }
  .viewer {
    display: grid;
    grid-template-rows: 1fr auto;
    min-width: 0;
    min-height: 0;
    overflow: hidden;
    background: rgba(15, 7, 30, 0.4);
  }
  .viewer-body {
    min-height: 0;
    padding: 14px 14px 0;
    overflow: auto;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .preview-frame {
    flex: 1 1 50%;
    min-height: 200px;
    max-height: 55%;
    border-radius: 12px;
    overflow: hidden;
    border: 1px solid var(--rule);
    background: rgba(0,0,0,0.25);
    display: grid;
    place-items: center;
  }
  .viewer-meta {
    display: grid;
    gap: 8px;
    padding: 0 2px;
  }
  .viewer-filename {
    font-size: 14px;
    font-weight: 600;
    letter-spacing: -0.01em;
    color: var(--milk);
    word-break: break-word;
  }
  .viewer-dl {
    display: grid;
    grid-template-columns: 90px minmax(0, 1fr);
    gap: 6px 12px;
    font-family: var(--mono);
    font-size: 11px;
    margin: 0;
  }
  .viewer-dl dt {
    color: var(--milk-faint);
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }
  .viewer-dl dd {
    margin: 0;
    color: var(--milk);
    text-align: right;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-variant-numeric: tabular-nums;
  }
  .viewer-foot-actions {
    padding: 10px 14px 12px;
    border-top: 1px solid var(--rule-soft);
    display: flex;
    gap: 8px;
    justify-content: flex-end;
    flex-shrink: 0;
  }
  .viewer-action {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 8px 14px;
    border-radius: 8px;
    text-decoration: none;
    font-family: var(--sans);
    font-size: 12px;
    font-weight: 500;
    border: 1px solid rgba(255,255,255,0.08);
    background: rgba(255,255,255,0.04);
    color: var(--milk);
  }
  .viewer-action:hover {
    background: rgba(255,255,255,0.08);
  }
  .viewer-action-primary {
    background: var(--asset-accent, var(--violet-hot));
    color: var(--ink);
    border-color: transparent;
    font-weight: 600;
  }
  .viewer-action-primary:hover {
    background: var(--asset-accent, var(--violet-hot));
    filter: brightness(1.08);
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
      max-height: 320px;
      overflow-y: auto;
    }
    .viewer {
      overflow: visible;
    }
    .viewer-body {
      padding-bottom: 14px;
      overflow: visible;
    }
    .preview-frame {
      min-height: 360px;
      max-height: none;
    }
  }
  @media (max-width: 720px) {
    body { padding: 0; }
    main { padding: 12px; }
    .topbar {
      flex-direction: column;
      align-items: flex-start;
    }
    .finder-bar {
      padding-inline: 12px;
    }
    .finder-title {
      font-size: 12px;
    }
    .file-list-header,
    .file-row {
      grid-template-columns: 20px minmax(0, 1fr) 70px;
    }
    .file-list-header .hdr-type,
    .file-row-type { display: none; }
    .preview-frame {
      min-height: 240px;
    }
  }
</style>
</head>
<body>
<main class="shell">
  <div class="topbar">
    <a href="https://fastsha.red" class="brand">fastshared<span class="brand-dot">.</span></a>
    <span class="meta-chip" data-expires-at="${expiresIso}" data-expired="false">${safeRemaining}</span>
  </div>

  <header class="finder-bar">
    <div class="finder-title">
      <strong>${fileCount}</strong> ${fileCount === 1 ? 'file' : 'files'}
      <span class="finder-title-sep">·</span>
      ${safeTotalBytes}
    </div>
    <div class="finder-actions">
      <a class="finder-btn" href="${safeCanonical}" rel="noopener">Copy link</a>
      <a class="finder-btn" data-viewer-download-top href="${escapeHtml(selected.downloadUrl)}" download rel="noopener">Download</a>
    </div>
  </header>

  <section class="browser" data-bundle-gallery aria-label="Bundle viewer">
    <div class="browser-body">
      <aside class="sidebar" aria-label="Files">
        <div class="file-list-header" aria-hidden="true">
          <span></span>
          <span>Name</span>
          <span class="hdr-size">Size</span>
          <span class="hdr-type">Kind</span>
        </div>
        <div class="file-list" role="listbox" aria-label="Bundle files">
          ${cards}
        </div>
      </aside>
      <section class="viewer" aria-label="Selected file preview">
        <div class="viewer-body">
          <div class="preview-frame" data-viewer-frame>${renderBundlePreviewMedia(selected, selectedKind)}</div>
          <div class="viewer-meta">
            <div class="viewer-filename" data-viewer-title>${escapeHtml(selected.filename)}</div>
            <dl class="viewer-dl">
              <dt>Kind</dt><dd data-viewer-kind>${escapeHtml(bundleTypeLabel(selectedKind))}</dd>
              <dt>Size</dt><dd data-viewer-size>${escapeHtml(formatBytes(selected.sizeBytes))}</dd>
              <dt>Type</dt><dd>${escapeHtml(selected.contentType)}</dd>
            </dl>
          </div>
        </div>
        <div class="viewer-foot-actions">
          <a class="viewer-action" href="${safeCanonical}" rel="noopener">Open link</a>
          <a class="viewer-action viewer-action-primary" data-viewer-download href="${escapeHtml(selected.downloadUrl)}" download rel="noopener">Download</a>
        </div>
      </section>
    </div>
  </section>

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
  var kindEl = document.querySelector('[data-viewer-kind]');
  var sizeEl = document.querySelector('[data-viewer-size]');
  var downloadEl = document.querySelector('[data-viewer-download]');
  var downloadTopEl = document.querySelector('[data-viewer-download-top]');
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
    if (kindEl) kindEl.textContent = kind;
    if (sizeEl) sizeEl.textContent = size;
    if (downloadEl) {
      downloadEl.setAttribute('href', downloadUrl);
      downloadEl.setAttribute('style', '--asset-accent: var(--' + accent + ')');
    }
    if (downloadTopEl) {
      downloadTopEl.setAttribute('href', downloadUrl);
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
