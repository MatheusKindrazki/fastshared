import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { mkdtemp, readFile, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { Writable } from 'node:stream';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
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

describe('CLI upload flow', () => {
  let server: ReturnType<typeof createServer> | undefined;
  let requests: RecordedRequest[] = [];

  beforeEach(() => {
    requests = [];
  });

  afterEach(async () => {
    if (!server) return;
    await new Promise<void>((resolve) => server!.close(() => resolve()));
    server = undefined;
  });

  it('registers a CLI device, uploads a file, completes it, and prints URL only', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-cli-flow-'));
    const file = join(dir, 'hello.txt');
    const config = join(dir, 'config.json');
    await writeFile(file, 'hello world');

    const apiUrl = await startMockApi(async (req, res, body) => {
      requests.push({ method: req.method ?? '', url: req.url ?? '', headers: req.headers, body });
      if (req.method === 'POST' && req.url === '/v1/devices') {
        return json(res, 201, { deviceId: 'dev_cli_1', deviceToken: 'tok_cli_1' });
      }
      if (req.method === 'POST' && req.url === '/v1/uploads') {
        expect(req.headers.authorization).toBe('Bearer tok_cli_1');
        const parsed = JSON.parse(body.toString()) as Record<string, unknown>;
        expect(parsed.retentionPolicy).toBe('oneHour');
        return json(res, 200, {
          uploadId: 'upl_1',
          upload: {
            mode: 'single',
            url: `${apiUrl}/r2/object`,
            method: 'PUT',
            headers: { 'content-type': 'text/plain', 'content-length': '11' },
            expiresAt: new Date(Date.now() + 900_000).toISOString(),
          },
          shortUrl: 'https://fastsha.red/s/pending',
          token: 'pending',
          expiresAt: new Date(Date.now() + 3_600_000).toISOString(),
          deleteAfter: new Date(Date.now() + 90_000_000).toISOString(),
          linkStatus: 'pending',
          retentionPolicy: 'oneHour',
        });
      }
      if (req.method === 'PUT' && req.url === '/r2/object') {
        expect(body.toString()).toBe('hello world');
        res.writeHead(200, { etag: '"etag-1"' });
        res.end();
        return;
      }
      if (req.method === 'POST' && req.url === '/v1/uploads/upl_1/complete') {
        expect(req.headers.authorization).toBe('Bearer tok_cli_1');
        return json(res, 200, {
          assetId: '11111111-1111-4111-8111-111111111111',
          shortUrl: 'https://fastsha.red/s/finaltoken',
          token: 'finaltoken',
          expiresAt: new Date(Date.now() + 3_600_000).toISOString(),
          deleteAfter: new Date(Date.now() + 90_000_000).toISOString(),
          linkStatus: 'active',
          retentionPolicy: 'oneHour',
        });
      }
      return json(res, 404, { code: 'not_found', detail: req.url });
    });

    const stdout = new MemoryWritable();
    const stderr = new MemoryWritable();
    const code = await runCli([file, '--api-url', apiUrl, '--config', config], {
      stdout,
      stderr,
      stdin: process.stdin,
      env: {},
      cwd: dir,
    });

    expect(code).toBe(0);
    expect(stdout.text()).toBe('https://fastsha.red/s/finaltoken\n');
    expect(stderr.text()).toContain('Uploading hello.txt');
    expect(JSON.parse(await readFile(config, 'utf8'))).toMatchObject({
      deviceId: 'dev_cli_1',
      deviceToken: 'tok_cli_1',
      apiBaseUrl: apiUrl,
    });
    expect((await stat(config)).mode & 0o777).toBe(0o600);
    expect(requests.map((r) => `${r.method} ${r.url}`)).toEqual([
      'POST /v1/devices',
      'POST /v1/uploads',
      'PUT /r2/object',
      'POST /v1/uploads/upl_1/complete',
    ]);
  });

  it('prints structured JSON when requested', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-cli-json-'));
    const file = join(dir, 'hello.txt');
    await writeFile(file, 'hello world');

    const apiUrl = await startMockApi(async (req, res, body) => {
      if (req.method === 'POST' && req.url === '/v1/uploads') {
        return json(res, 200, {
          uploadId: 'upl_1',
          upload: {
            mode: 'single',
            url: `${apiUrl}/r2/object`,
            method: 'PUT',
            headers: { 'content-type': 'text/plain', 'content-length': '11' },
            expiresAt: new Date(Date.now() + 900_000).toISOString(),
          },
          retentionPolicy: 'oneHour',
        });
      }
      if (req.method === 'PUT' && req.url === '/r2/object') {
        res.writeHead(200);
        res.end();
        return;
      }
      if (req.method === 'POST' && req.url === '/v1/uploads/upl_1/complete') {
        return json(res, 200, {
          assetId: '11111111-1111-4111-8111-111111111111',
          shortUrl: 'https://fastsha.red/s/json',
          token: 'json',
          expiresAt: '2026-04-25T20:00:00.000Z',
          deleteAfter: '2026-04-26T20:00:00.000Z',
          linkStatus: 'active',
          retentionPolicy: 'oneHour',
        });
      }
      return json(res, 404, {});
    });

    const stdout = new MemoryWritable();
    const code = await runCli(
      [file, '--api-url', apiUrl, '--json', '--quiet'],
      {
        stdout,
        stderr: new MemoryWritable(),
        stdin: process.stdin,
        env: { FASTSHARED_DEVICE_TOKEN: 'tok_env' },
        cwd: dir,
      },
    );

    expect(code).toBe(0);
    expect(JSON.parse(stdout.text())).toMatchObject({
      shortUrl: 'https://fastsha.red/s/json',
      token: 'json',
      linkStatus: 'active',
    });
  });

  it('returns non-zero for backend quota errors', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-cli-error-'));
    const file = join(dir, 'too-big.bin');
    await writeFile(file, 'x');

    const apiUrl = await startMockApi(async (req, res) => {
      if (req.method === 'POST' && req.url === '/v1/uploads') {
        return json(res, 413, {
          title: 'Payload Too Large',
          code: 'file_too_large',
          detail: 'size exceeds limit',
        });
      }
      return json(res, 404, {});
    });

    const stderr = new MemoryWritable();
    const code = await runCli([file, '--api-url', apiUrl, '--quiet'], {
      stdout: new MemoryWritable(),
      stderr,
      stdin: process.stdin,
      env: { FASTSHARED_DEVICE_TOKEN: 'tok_env' },
      cwd: dir,
    });

    expect(code).toBe(1);
    expect(stderr.text()).toContain('HTTP 413 file_too_large');
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

function json(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}
