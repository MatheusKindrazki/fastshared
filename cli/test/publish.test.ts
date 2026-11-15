import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { Writable } from 'node:stream';
import { afterEach, describe, expect, it } from 'vitest';
import { runCli } from '../src/cli.js';

class MemoryWritable extends Writable {
  chunks: string[] = [];

  override _write(
    chunk: Buffer | string,
    _encoding: BufferEncoding,
    callback: (error?: Error | null) => void,
  ): void {
    this.chunks.push(chunk.toString());
    callback();
  }

  text(): string {
    return this.chunks.join('');
  }
}

interface RecordedRequest {
  method: string;
  url: string;
  headers: IncomingMessage['headers'];
  body: Buffer;
}

describe('publication commands', () => {
  let server: ReturnType<typeof createServer> | undefined;
  let requests: RecordedRequest[] = [];

  afterEach(async () => {
    if (!server) return;
    await new Promise<void>((resolve) => server!.close(() => resolve()));
    server = undefined;
  });

  it('publishes a directory as a site and prints only the stable URL', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-pub-site-'));
    const site = join(dir, 'notes');
    await mkdir(site);
    await writeFile(join(site, 'index.html'), '<p>notes</p>');
    requests = [];

    const apiUrl = await startMockApi(async (req, res, body) => {
      requests.push(recorded(req, body));
      if (req.method === 'POST' && req.url === '/v1/publications') {
        const parsed = JSON.parse(body.toString()) as Record<string, unknown>;
        expect(parsed.kind).toBe('site');
        expect(parsed.filename).toBe('notes.zip');
        expect(parsed.contentType).toBe('application/zip');
        expect(parsed.title).toBe('Notes');
        expect(req.headers.authorization).toBe('Bearer tok_pub');
        return json(res, 200, slot(apiUrl, 1));
      }
      if (req.method === 'PUT' && req.url === '/r2/pub') {
        expect(body.subarray(0, 2).toString()).toBe('PK');
        expect(body.length).toBeGreaterThan(0);
        res.writeHead(200);
        res.end();
        return;
      }
      if (req.method === 'POST' && req.url === '/v1/publications/pub_1/versions/1/complete') {
        return json(res, 200, ready(1, body.length));
      }
      return json(res, 404, { code: 'not_found' });
    });

    const stdout = new MemoryWritable();
    const stderr = new MemoryWritable();
    const code = await run(dir, ['publish', site, '--title', 'Notes', '--api-url', apiUrl], stdout, stderr);

    expect(code).toBe(0);
    expect(stdout.text()).toBe('https://p-my-site.fastsha.red\n');
    expect(stderr.text()).toContain('Publishing site');
    expect(stderr.text()).not.toContain('https://p-my-site.fastsha.red');
    expect(requests.map((item) => `${item.method} ${item.url}`)).toEqual([
      'POST /v1/publications',
      'PUT /r2/pub',
      'POST /v1/publications/pub_1/versions/1/complete',
    ]);
  });

  it('publishes a PDF and a regular file without zipping them', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-pub-files-'));
    await writeFile(join(dir, 'deck.pdf'), '%PDF-1.7');
    await writeFile(join(dir, 'notes.txt'), 'hello');
    const seen: Array<Record<string, unknown>> = [];

    const apiUrl = await startMockApi(async (req, res, body) => {
      if (req.method === 'POST' && req.url === '/v1/publications') {
        seen.push(JSON.parse(body.toString()) as Record<string, unknown>);
        return json(res, 200, slot(apiUrl, 1));
      }
      if (req.method === 'PUT' && req.url === '/r2/pub') {
        res.writeHead(200);
        res.end();
        return;
      }
      if (req.method === 'POST' && req.url === '/v1/publications/pub_1/versions/1/complete') {
        return json(res, 200, ready(1, 1));
      }
      return json(res, 404, {});
    });

    expect(await run(dir, ['publish', 'deck.pdf', '--quiet', '--api-url', apiUrl])).toBe(0);
    expect(await run(dir, ['publish', 'notes.txt', '--quiet', '--api-url', apiUrl])).toBe(0);
    expect(seen[0]).toMatchObject({ kind: 'pdf', filename: 'deck.pdf', contentType: 'application/pdf' });
    expect(seen[1]).toMatchObject({ kind: 'file', filename: 'notes.txt', contentType: 'text/plain' });
  });

  it('zips a single HTML file as index.html', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-pub-html-'));
    await writeFile(join(dir, 'page.html'), '<h1>Hi</h1>');
    let uploaded = Buffer.alloc(0);
    let createBody: Record<string, unknown> = {};

    const apiUrl = await startMockApi(async (req, res, body) => {
      if (req.method === 'POST' && req.url === '/v1/publications') {
        createBody = JSON.parse(body.toString()) as Record<string, unknown>;
        return json(res, 200, slot(apiUrl, 1));
      }
      if (req.method === 'PUT' && req.url === '/r2/pub') {
        uploaded = body;
        res.writeHead(200);
        res.end();
        return;
      }
      if (req.method === 'POST' && req.url === '/v1/publications/pub_1/versions/1/complete') {
        return json(res, 200, ready(1, uploaded.length));
      }
      return json(res, 404, {});
    });

    const stdout = new MemoryWritable();
    const code = await run(dir, ['publish', 'page.html', '--json', '--quiet', '--api-url', apiUrl], stdout);
    expect(code).toBe(0);
    expect(createBody).toMatchObject({ kind: 'site', filename: 'page.zip', contentType: 'application/zip' });
    expect(uploaded.includes(Buffer.from('index.html'))).toBe(true);
    expect(uploaded.includes(Buffer.from('<h1>Hi</h1>'))).toBe(true);
    expect(JSON.parse(stdout.text())).toEqual({
      id: 'pub_1',
      slug: 'my-site',
      url: 'https://p-my-site.fastsha.red',
      version: 1,
      fileCount: 1,
      totalBytes: uploaded.length,
    });
  });

  it('updates a publication on the same URL', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-pub-update-'));
    await writeFile(join(dir, 'page.html'), '<p>next</p>');
    requests = [];

    const apiUrl = await startMockApi(async (req, res, body) => {
      requests.push(recorded(req, body));
      if (req.method === 'POST' && req.url === '/v1/publications/my-slug/versions') {
        expect(JSON.parse(body.toString())).toMatchObject({ kind: 'site', title: 'Next' });
        return json(res, 200, slot(apiUrl, 2));
      }
      if (req.method === 'PUT' && req.url === '/r2/pub') {
        res.writeHead(200);
        res.end();
        return;
      }
      if (req.method === 'POST' && req.url === '/v1/publications/pub_1/versions/2/complete') {
        return json(res, 200, ready(2, 20));
      }
      return json(res, 404, {});
    });

    const stdout = new MemoryWritable();
    const code = await run(
      dir,
      ['publish', 'page.html', '--update', 'my-slug', '--title', 'Next', '--quiet', '--api-url', apiUrl],
      stdout,
    );
    expect(code).toBe(0);
    expect(stdout.text()).toBe('https://p-my-site.fastsha.red\n');
    expect(requests.map((item) => `${item.method} ${item.url}`)).toEqual([
      'POST /v1/publications/my-slug/versions',
      'PUT /r2/pub',
      'POST /v1/publications/pub_1/versions/2/complete',
    ]);
  });

  it('tells Free users that same-URL updates are a Pro feature', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-pub-402-'));
    await writeFile(join(dir, 'page.html'), '<p>next</p>');
    requests = [];
    const upgradeUrl = 'https://fastsha.red/pricing';

    const apiUrl = await startMockApi(async (req, res, body) => {
      requests.push(recorded(req, body));
      if (req.method === 'POST' && req.url === '/v1/publications/my-slug/versions') {
        return json(res, 402, {
          title: 'Payment Required',
          code: 'payment_required',
          upgradeUrl,
          detail: 'Pro required',
        });
      }
      return json(res, 404, {});
    });

    const stderr = new MemoryWritable();
    const code = await run(
      dir,
      ['publish', 'page.html', '--update', 'my-slug', '--quiet', '--api-url', apiUrl],
      new MemoryWritable(),
      stderr,
    );
    expect(code).toBe(2);
    expect(stderr.text()).toContain('Same-URL updates are a Pro feature');
    expect(stderr.text()).toContain(upgradeUrl);
    expect(requests.map((item) => `${item.method} ${item.url}`)).toEqual(['POST /v1/publications/my-slug/versions']);
  });

  it('polls after HTTP 202 until the publication is ready', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-pub-poll-'));
    await writeFile(join(dir, 'notes.txt'), 'hello');
    let polls = 0;
    requests = [];

    const apiUrl = await startMockApi(async (req, res, body) => {
      requests.push(recorded(req, body));
      if (req.method === 'POST' && req.url === '/v1/publications') return json(res, 200, slot(apiUrl, 1));
      if (req.method === 'PUT' && req.url === '/r2/pub') {
        res.writeHead(200);
        res.end();
        return;
      }
      if (req.method === 'POST' && req.url === '/v1/publications/pub_1/versions/1/complete') {
        res.writeHead(202, {
          'content-type': 'application/json',
          location: '/v1/publications/pub_1/versions/1/status',
          'retry-after': '0',
        });
        res.end(JSON.stringify({ status: 'processing' }));
        return;
      }
      if (req.method === 'GET' && req.url === '/v1/publications/pub_1/versions/1/status') {
        polls += 1;
        if (polls === 1) return json(res, 200, { status: 'processing' });
        return json(res, 200, { status: 'ready', ...ready(1, 5) });
      }
      return json(res, 404, { code: 'not_found', detail: req.url });
    });

    const stdout = new MemoryWritable();
    const stderr = new MemoryWritable();
    const code = await run(
      dir,
      ['publish', 'notes.txt', '--api-url', apiUrl],
      stdout,
      stderr,
      { FASTSHARED_PUBLICATION_POLL_INTERVAL_MS: '20', FASTSHARED_PUBLICATION_POLL_TIMEOUT_MS: '2000' },
    );
    expect(code).toBe(0);
    expect(stdout.text()).toBe('https://p-my-site.fastsha.red\n');
    expect(stderr.text()).toContain('Publication is processing...');
    expect(polls).toBe(2);
    expect(requests.some((item) => item.url === '/v1/publications/pub_1/versions/1')).toBe(false);
  });

  it('stops polling with a timeout when the publication stays in progress', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-pub-timeout-'));
    await writeFile(join(dir, 'notes.txt'), 'hello');

    const apiUrl = await startMockApi(async (req, res) => {
      if (req.method === 'POST' && req.url === '/v1/publications') return json(res, 200, slot(apiUrl, 1));
      if (req.method === 'PUT' && req.url === '/r2/pub') {
        res.writeHead(200);
        res.end();
        return;
      }
      if (req.method === 'POST' && req.url === '/v1/publications/pub_1/versions/1/complete') {
        return json(res, 202, { status: 'processing' });
      }
      if (req.method === 'GET' && req.url === '/v1/publications/pub_1/versions/1') {
        return json(res, 200, { status: 'processing' });
      }
      return json(res, 404, {});
    });

    const stderr = new MemoryWritable();
    const code = await run(dir, ['publish', 'notes.txt', '--quiet', '--api-url', apiUrl], new MemoryWritable(), stderr, {
      FASTSHARED_PUBLICATION_POLL_INTERVAL_MS: '15',
      FASTSHARED_PUBLICATION_POLL_TIMEOUT_MS: '40',
    });
    expect(code).toBe(1);
    expect(stderr.text()).toContain('still processing');
    expect(stderr.text()).toContain('40ms');
  });

  it('rejects a poll URL on another host', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-pub-poll-host-'));
    await writeFile(join(dir, 'notes.txt'), 'hello');

    const apiUrl = await startMockApi(async (req, res) => {
      if (req.method === 'POST' && req.url === '/v1/publications') return json(res, 200, slot(apiUrl, 1));
      if (req.method === 'PUT' && req.url === '/r2/pub') {
        res.writeHead(200);
        res.end();
        return;
      }
      if (req.method === 'POST' && req.url === '/v1/publications/pub_1/versions/1/complete') {
        res.writeHead(202, {
          'content-type': 'application/json',
          location: 'https://example.invalid/poll',
        });
        res.end(JSON.stringify({ status: 'processing' }));
        return;
      }
      return json(res, 500, {});
    });

    const stderr = new MemoryWritable();
    const code = await run(dir, ['publish', 'notes.txt', '--quiet', '--api-url', apiUrl], new MemoryWritable(), stderr);
    expect(code).toBe(1);
    expect(stderr.text()).toContain('not on the API host');
  });

  it.each(['no_entry', 'too_many_files', 'ratio', 'path'] as const)(
    'explains unpack_error %s',
    async (unpackError) => {
      const dir = await mkdtemp(join(tmpdir(), 'fastshared-pub-unpack-'));
      await writeFile(join(dir, 'page.html'), '<p>x</p>');
      const apiUrl = await startMockApi(async (req, res) => {
        if (req.method === 'POST' && req.url === '/v1/publications') return json(res, 200, slot(apiUrl, 1));
        if (req.method === 'PUT' && req.url === '/r2/pub') {
          res.writeHead(200);
          res.end();
          return;
        }
        if (req.method === 'POST' && req.url === '/v1/publications/pub_1/versions/1/complete') {
          return json(res, 422, {
            title: 'Unprocessable Content',
            code: 'unpack_error',
            unpack_error: unpackError,
          });
        }
        return json(res, 404, {});
      });

      const stderr = new MemoryWritable();
      const code = await run(dir, ['publish', 'page.html', '--quiet', '--api-url', apiUrl], new MemoryWritable(), stderr);
      expect(code).toBe(1);
      expect(stderr.text()).toContain(expectedUnpackMessage(unpackError));
    },
  );

  it('lists, revokes, and shows opens', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-pub-manage-'));
    requests = [];
    const apiUrl = await startMockApi(async (req, res, body) => {
      requests.push(recorded(req, body));
      if (req.method === 'GET' && req.url === '/v1/publications') {
        return json(res, 200, {
          publications: [
            {
              id: 'pub_1',
              slug: 'my-site',
              url: 'https://p-my-site.fastsha.red',
              title: 'Notes',
              kind: 'site',
              status: 'active',
              version: 2,
              expiresAt: null,
              opens7d: 3,
            },
          ],
        });
      }
      if (req.method === 'POST' && req.url === '/v1/publications/my-site/revoke') {
        return json(res, 200, { id: 'pub_1', status: 'revoked' });
      }
      if (req.method === 'GET' && req.url === '/v1/publications/pub_1/opens') {
        return json(res, 200, {
          id: 'pub_1',
          versions: [{ version: 2, count: 3, lastOpenedAt: '2026-11-15T18:00:00.000Z' }],
        });
      }
      return json(res, 404, {});
    });

    const listOut = new MemoryWritable();
    expect(await run(dir, ['publications', 'list', '--api-url', apiUrl], listOut)).toBe(0);
    expect(listOut.text()).toContain('https://p-my-site.fastsha.red');
    expect(listOut.text()).toContain('3 opens/7d');
    expect(listOut.text()).toContain('Notes');

    const listJson = new MemoryWritable();
    expect(await run(dir, ['publications', 'list', '--json', '--api-url', apiUrl], listJson)).toBe(0);
    expect(JSON.parse(listJson.text()).publications).toHaveLength(1);

    const revokeOut = new MemoryWritable();
    expect(await run(dir, ['publications', 'revoke', 'my-site', '--api-url', apiUrl], revokeOut)).toBe(0);
    expect(revokeOut.text()).toBe('revoked pub_1\n');

    const opensOut = new MemoryWritable();
    expect(await run(dir, ['publications', 'opens', 'pub_1', '--json', '--api-url', apiUrl], opensOut)).toBe(0);
    expect(JSON.parse(opensOut.text())).toEqual({
      id: 'pub_1',
      versions: [{ version: 2, count: 3, lastOpenedAt: '2026-11-15T18:00:00.000Z' }],
    });
    expect(requests.map((item) => `${item.method} ${item.url}`)).toEqual([
      'GET /v1/publications',
      'GET /v1/publications',
      'POST /v1/publications/my-site/revoke',
      'GET /v1/publications/pub_1/opens',
    ]);
  });

  it('prints publication help without calling the API', async () => {
    const stdout = new MemoryWritable();
    const code = await runCli(['publish', '--help'], {
      stdout,
      stderr: new MemoryWritable(),
      stdin: process.stdin,
      env: {},
      cwd: process.cwd(),
    });
    expect(code).toBe(0);
    expect(stdout.text()).toContain('fastshared publish');
    expect(stdout.text()).toContain('require the publications API');
  });

  async function startMockApi(
    handler: (req: IncomingMessage, res: ServerResponse, body: Buffer) => Promise<void> | void,
  ): Promise<string> {
    server = createServer(async (req, res) => {
      const chunks: Buffer[] = [];
      for await (const chunk of req) chunks.push(Buffer.from(chunk as Buffer));
      await handler(req, res, Buffer.concat(chunks));
    });
    await new Promise<void>((resolve) => server!.listen(0, '127.0.0.1', () => resolve()));
    const address = server.address();
    if (!address || typeof address === 'string') throw new Error('bad server address');
    return `http://127.0.0.1:${address.port}`;
  }
});

function run(
  cwd: string,
  argv: string[],
  stdout = new MemoryWritable(),
  stderr = new MemoryWritable(),
  env: NodeJS.ProcessEnv = {},
): Promise<number> {
  return runCli(argv, {
    stdout,
    stderr,
    stdin: process.stdin,
    env: { FASTSHARED_DEVICE_TOKEN: 'tok_pub', ...env },
    cwd,
  });
}

function recorded(req: IncomingMessage, body: Buffer): RecordedRequest {
  return { method: req.method ?? '', url: req.url ?? '', headers: req.headers, body };
}

function json(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

function slot(apiUrl: string, version: number) {
  return {
    id: 'pub_1',
    slug: 'my-site',
    url: 'https://p-my-site.fastsha.red',
    version,
    upload: {
      url: `${apiUrl}/r2/pub`,
      method: 'PUT',
      headers: { 'content-type': 'application/octet-stream' },
    },
  };
}

function ready(version: number, totalBytes: number) {
  return {
    url: 'https://p-my-site.fastsha.red',
    version,
    fileCount: 1,
    totalBytes,
  };
}

function expectedUnpackMessage(code: 'no_entry' | 'too_many_files' | 'ratio' | 'path'): string {
  switch (code) {
    case 'no_entry':
      return 'no HTML entry';
    case 'too_many_files':
      return 'too many files';
    case 'ratio':
      return 'compression ratio';
    case 'path':
      return 'path that is not allowed';
  }
}
