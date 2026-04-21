// HTML preview page rendered by GET /s/:token when the client sends
// `Accept: text/html`. Pure string construction — no Hono imports, no env
// access. Callers hand in everything needed and we hand back a Response.
//
// Palette tokens come from `web/.impeccable.md` (the locked brand spec).

const COLORS = {
  ink: '#070318',
  nightshade: '#1d0d4b',
  deepViolet: '#3b1f86',
  amber: '#ff9f47',
  ember: '#ffc487',
  coral: '#ff4e7c',
  cream: '#ffe0b8',
  milk: '#fafaff',
  violetHot: '#9d7aff',
  violetSoft: '#c1a9ff',
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
    --amber: ${COLORS.amber};
    --ember: ${COLORS.ember};
    --coral: ${COLORS.coral};
    --milk: ${COLORS.milk};
    --violet-hot: ${COLORS.violetHot};
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
    color: var(--amber);
    font-variant-numeric: tabular-nums;
  }
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
    <div class="countdown-value" data-expires-at="${expiresIso}" data-expired="false">${safeRemaining}</div>
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
    --amber: ${COLORS.amber};
    --milk: ${COLORS.milk};
    --violet-hot: ${COLORS.violetHot};
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
    color: var(--amber);
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

// Bundle preview page — N files behind one short link. Visual tokens come
// from `web/.impeccable.md`, same palette as the single preview so the brand
// reads consistently. The "Download all" button is a stub for the M2 cut;
// ZIP packaging lands in a later milestone.
export interface BundlePreviewItem {
  assetId: string;
  filename: string;
  sizeBytes: number;
  contentType: string;
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

export function renderBundlePreviewPage(args: RenderBundlePreviewPageArgs): Response {
  const now = args.requestNow ?? new Date();
  const msUntilExpiry = Math.max(0, args.expiresAt.getTime() - now.getTime());
  const humanRemaining = humanizeMs(msUntilExpiry);
  const expiresIso = args.expiresAt.toISOString();

  const safeRemaining = escapeHtml(humanRemaining);
  const safeCanonical = escapeHtml(args.canonicalUrl);
  const safeOgImage = escapeHtml(args.ogImageUrl);

  const fileCount = args.items.length;
  const ogTitle = `${fileCount} ${fileCount === 1 ? 'arquivo' : 'arquivos'} via FastShared`;
  // OG description: enumerate first two filenames + "+N more" trail.
  const previewNames = args.items.slice(0, 2).map((i) => i.filename);
  const remainder = Math.max(0, fileCount - previewNames.length);
  const ogDescription =
    previewNames.length > 0
      ? `${previewNames.join(', ')}${remainder > 0 ? ` +${remainder} more` : ''}`
      : 'Bundle via FastShared';
  const safeOgTitle = escapeHtml(ogTitle);
  const safeOgDescription = escapeHtml(ogDescription);

  const cards = args.items
    .map((item) => {
      const safeFilename = escapeHtml(item.filename);
      const safeSize = escapeHtml(formatBytes(item.sizeBytes));
      const safeCt = escapeHtml(item.contentType);
      const safeDownload = escapeHtml(item.downloadUrl);
      const glyph = fileGlyphFor(item.contentType, item.filename);
      return `<li class="card">
  <div class="card-glyph" aria-hidden="true">${glyph}</div>
  <div class="card-meta">
    <div class="card-name" title="${safeFilename}">${safeFilename}</div>
    <div class="card-sub">
      <span>${safeSize}</span>
      <span class="dot" aria-hidden="true">&middot;</span>
      <span class="card-ct">${safeCt}</span>
    </div>
  </div>
  <a class="card-dl" href="${safeDownload}" download rel="noopener" aria-label="Download ${safeFilename}">Download</a>
</li>`;
    })
    .join('\n');

  const headerLabel = `${fileCount} ${fileCount === 1 ? 'arquivo' : 'arquivos'} via FastShared`;
  const safeHeaderLabel = escapeHtml(headerLabel);

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
    --deep-violet: ${COLORS.deepViolet};
    --amber: ${COLORS.amber};
    --coral: ${COLORS.coral};
    --milk: ${COLORS.milk};
    --violet-hot: ${COLORS.violetHot};
    --rule: ${COLORS.rule};
    --milk-dim: ${COLORS.milkDim};
    --milk-faint: ${COLORS.milkFaint};
    --milk-ghost: ${COLORS.milkGhost};
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
  header { margin-bottom: 24px; }
  .brand {
    display: inline-block;
    font-size: 22px;
    font-weight: 700;
    letter-spacing: -0.025em;
    color: var(--milk);
    text-decoration: none;
  }
  .brand-dot { color: var(--violet-hot); }
  h1 {
    margin: 24px 0 8px;
    font-size: 26px;
    font-weight: 700;
    letter-spacing: -0.025em;
    color: var(--milk);
  }
  .countdown {
    margin: 8px 0 24px;
    font-family: var(--mono);
    font-size: 12px;
    color: var(--milk-dim);
    letter-spacing: 0.04em;
  }
  .countdown[data-expired="true"] { color: var(--coral); }
  .list {
    list-style: none;
    padding: 0;
    margin: 0 0 24px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .card {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 16px 18px;
    background: var(--nightshade);
    border: 1px solid var(--rule);
    border-radius: 16px;
  }
  .card-glyph {
    flex: 0 0 auto;
    font-size: 32px;
    line-height: 1;
  }
  .card-meta {
    flex: 1 1 auto;
    min-width: 0;
  }
  .card-name {
    font-size: 15px;
    font-weight: 600;
    letter-spacing: -0.01em;
    color: var(--milk);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .card-sub {
    margin-top: 4px;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--milk-dim);
    display: flex;
    gap: 8px;
    align-items: center;
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }
  .card-sub .dot { color: var(--milk-faint); }
  .card-ct {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 240px;
  }
  .card-dl {
    flex: 0 0 auto;
    padding: 9px 16px;
    background: var(--violet-hot);
    color: var(--ink);
    border-radius: 999px;
    text-decoration: none;
    font-family: var(--sans);
    font-weight: 600;
    font-size: 13px;
    letter-spacing: -0.005em;
    transition: filter 120ms ease, transform 120ms ease;
  }
  .card-dl:hover, .card-dl:focus {
    filter: brightness(1.08);
    transform: scale(1.02);
  }
  .download-all {
    display: block;
    width: 100%;
    padding: 14px 24px;
    background: transparent;
    color: var(--milk-dim);
    border: 1px dashed var(--milk-ghost);
    border-radius: 999px;
    text-align: center;
    font-family: var(--sans);
    font-weight: 600;
    font-size: 14px;
    letter-spacing: -0.01em;
    cursor: not-allowed;
  }
  .download-all small {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--milk-faint);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    margin-left: 6px;
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

  <h1>${safeHeaderLabel}</h1>
  <div class="countdown" data-expires-at="${expiresIso}" data-expired="false" aria-live="polite">expires in ${safeRemaining}</div>

  <ul class="list">
    ${cards}
  </ul>

  <button class="download-all" type="button" disabled aria-disabled="true">
    Download all <small>em breve</small>
  </button>

  <footer>
    <a href="https://fastsha.red">fastsha.red</a> &middot; share files, watch them expire.
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
    if (d > 0) return 'expires in ' + d + 'd ' + pad(h) + 'h ' + pad(m) + 'm';
    if (h > 0) return 'expires in ' + pad(h) + 'h ' + pad(m) + 'm ' + pad(s) + 's';
    return 'expires in ' + pad(m) + 'm ' + pad(s) + 's';
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
