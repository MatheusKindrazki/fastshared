import { describe, it, expect } from 'vitest';
import { renderPreviewPage, renderBundlePreviewPage, renderPendingPage } from '~/lib/previewPage';

const HOST = 'https://fastsha.red';

async function bodyOf(res: Response): Promise<string> {
  return await res.text();
}

describe('preview pages — LLM/agent fetch instructions', () => {
  it('single-file preview points an LLM at the /raw bytes URL', async () => {
    const res = renderPreviewPage({
      filename: 'photo.jpg',
      sizeBytes: 2_500_000,
      contentType: 'image/jpeg',
      expiresAt: new Date('2030-01-01T00:00:00Z'),
      downloadUrl: `${HOST}/s/TOKEN/download`,
      previewUrl: `${HOST}/s/TOKEN/raw`,
      canonicalUrl: `${HOST}/s/TOKEN`,
      ogImageUrl: `${HOST}/og-image.png`,
      requestNow: new Date('2026-01-01T00:00:00Z'),
    });
    const html = await bodyOf(res);

    // Machine-readable meta hints carry the raw-bytes URL and content type.
    expect(html).toContain('<meta name="ai:raw-url" content="https://fastsha.red/s/TOKEN/raw" />');
    expect(html).toContain('<meta name="ai:content-type" content="image/jpeg" />');
    expect(html).toContain('name="ai:download-url"');
    // Comment + visually-hidden block both name the raw URL.
    expect(html).toContain('fetch the raw bytes from this URL');
    expect(html).toContain('data-ai-instructions');
    // The hidden block must be inert: hidden + aria-hidden + clipped.
    expect(html).toMatch(/data-ai-instructions[^>]*hidden[^>]*aria-hidden="true"/);
  });

  it('does NOT let a crafted filename break out of the HTML comment', async () => {
    // A filename that tries to close the comment and inject a script.
    const evil = 'pwn--><script>alert(1)</script>.jpg';
    const res = renderPreviewPage({
      filename: evil,
      sizeBytes: 10,
      contentType: 'image/jpeg',
      expiresAt: new Date('2030-01-01T00:00:00Z'),
      downloadUrl: `${HOST}/s/TOKEN/download`,
      previewUrl: `${HOST}/s/TOKEN/raw`,
      canonicalUrl: `${HOST}/s/TOKEN`,
      ogImageUrl: `${HOST}/og-image.png`,
      requestNow: new Date('2026-01-01T00:00:00Z'),
    });
    const html = await bodyOf(res);

    // No live <script> tag anywhere — the payload must never become markup.
    expect(html).not.toContain('<script>alert(1)</script>');
    // The literal comment-closing sequence `-->` must not appear adjacent to
    // the injected payload (a zero-width space is inserted between the
    // hyphens, so `pwn-->` cannot survive verbatim).
    expect(html).not.toContain('pwn--><script');
  });

  it('bundle preview enumerates each file with its raw-bytes URL', async () => {
    const res = renderBundlePreviewPage({
      token: 'BUND',
      expiresAt: new Date('2030-01-01T00:00:00Z'),
      canonicalUrl: `${HOST}/b/BUND`,
      ogImageUrl: `${HOST}/og-image.png`,
      requestNow: new Date('2026-01-01T00:00:00Z'),
      items: [
        {
          assetId: 'a1',
          filename: 'one.png',
          sizeBytes: 100,
          contentType: 'image/png',
          previewUrl: `${HOST}/b/BUND/p/a1`,
          downloadUrl: `${HOST}/b/BUND/d/a1`,
        },
        {
          assetId: 'a2',
          filename: 'two.pdf',
          sizeBytes: 200,
          contentType: 'application/pdf',
          previewUrl: `${HOST}/b/BUND/p/a2`,
          downloadUrl: `${HOST}/b/BUND/d/a2`,
        },
      ],
    });
    const html = await bodyOf(res);

    expect(html).toContain('<meta name="ai:bundle" content="true" />');
    expect(html).toContain('<meta name="ai:file-count" content="2" />');
    // Each asset's raw URL must be present for the agent to fetch individually.
    expect(html).toContain('https://fastsha.red/b/BUND/p/a1');
    expect(html).toContain('https://fastsha.red/b/BUND/p/a2');
    expect(html).toContain('data-ai-instructions');
  });

  it('pending page tells an LLM the file is not ready and to retry', async () => {
    const res = renderPendingPage({
      filename: 'upload',
      sizeBytes: 0,
      expiresAt: new Date('2030-01-01T00:00:00Z'),
      canonicalUrl: `${HOST}/s/TOKEN`,
      requestNow: new Date('2026-01-01T00:00:00Z'),
    });
    const html = await bodyOf(res);

    expect(html).toContain('<meta name="ai:status" content="pending" />');
    expect(html).toContain('<meta name="ai:retry-url" content="https://fastsha.red/s/TOKEN" />');
    expect(html).toContain('still uploading');
  });
});
