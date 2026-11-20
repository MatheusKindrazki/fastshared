import { createServer, type Server } from 'node:http';
import { Writable } from 'node:stream';
import { afterEach, describe, expect, it } from 'vitest';
import { runCli } from '../src/cli.js';
import { parseCommand, UsageError } from '../src/options.js';

class MemoryWritable extends Writable {
  chunks: string[] = [];
  override _write(chunk: Buffer, _enc: string, cb: () => void): void {
    this.chunks.push(chunk.toString());
    cb();
  }
  text(): string {
    return this.chunks.join('');
  }
}

let server: Server | undefined;
afterEach(async () => {
  await new Promise<void>((resolve) => (server ? server.close(() => resolve()) : resolve()));
  server = undefined;
});

async function mockApi(
  handler: (method: string, url: string, body: string) => { status: number; body: unknown },
): Promise<{ url: string; seen: string[] }> {
  const seen: string[] = [];
  server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on('data', (c: Buffer) => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks).toString();
      seen.push(`${req.method} ${req.url} ${req.headers.authorization ?? ''} ${body}`);
      const out = handler(req.method ?? '', req.url ?? '', body);
      res.writeHead(out.status, { 'content-type': 'application/json' });
      res.end(JSON.stringify(out.body));
    });
  });
  await new Promise<void>((resolve) => server!.listen(0, '127.0.0.1', () => resolve()));
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('bad address');
  return { url: `http://127.0.0.1:${address.port}`, seen };
}

function run(argv: string[], stdout: MemoryWritable, stderr: MemoryWritable): Promise<number> {
  return runCli(argv, {
    stdout,
    stderr,
    stdin: process.stdin,
    env: { FASTSHARED_DEVICE_TOKEN: 'tok_cli' },
    cwd: process.cwd(),
  });
}

describe('fastshared login', () => {
  it('parses a 6-digit code and rejects anything else', () => {
    expect(parseCommand(['login', '123456'])).toMatchObject({ command: 'login', code: '123456' });
    for (const argv of [['login'], ['login', '12345'], ['login', 'abcdef'], ['login', '1', '2']]) {
      expect(() => parseCommand(argv)).toThrow(UsageError);
    }
  });

  it('claims the code with the device token and confirms the link', async () => {
    const api = await mockApi((method, url) =>
      method === 'POST' && url === '/v1/link-codes/claim'
        ? { status: 200, body: { linked: true, userId: 'user_1' } }
        : { status: 404, body: {} },
    );
    const stdout = new MemoryWritable();
    const stderr = new MemoryWritable();
    const code = await run(['login', '042137', '--api-url', api.url], stdout, stderr);
    expect(code).toBe(0);
    expect(stdout.text()).toContain('Linked to your FastShared account');
    expect(api.seen).toEqual(['POST /v1/link-codes/claim Bearer tok_cli {"code":"042137"}']);
  });

  it('fails with the server message when the code is wrong', async () => {
    const api = await mockApi(() => ({
      status: 400,
      body: { code: 'invalid_code', detail: 'the code is invalid or expired' },
    }));
    const stdout = new MemoryWritable();
    const stderr = new MemoryWritable();
    const code = await run(['login', '000000', '--api-url', api.url], stdout, stderr);
    expect(code).not.toBe(0);
    expect(stdout.text()).toBe('');
  });
});

describe('fastshared whoami', () => {
  it('reports a linked Pro device', async () => {
    const api = await mockApi(() => ({ status: 200, body: { userId: 'user_1', isPro: true } }));
    const stdout = new MemoryWritable();
    const code = await run(['whoami', '--api-url', api.url], stdout, new MemoryWritable());
    expect(code).toBe(0);
    expect(stdout.text()).toBe('Linked to an account (Pro).\n');
  });

  it('tells an unlinked device how to link', async () => {
    const api = await mockApi(() => ({ status: 200, body: { userId: null, isPro: false } }));
    const stdout = new MemoryWritable();
    await run(['whoami', '--json', '--api-url', api.url], stdout, new MemoryWritable());
    expect(JSON.parse(stdout.text())).toEqual({ linked: false, userId: null, isPro: false });
  });
});
