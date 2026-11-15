import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { afterEach, describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { FastSharedApi } from '../src/api.js';
import { createPublicationMcpServer } from '../src/mcp.js';

describe('publication MCP server', () => {
  let server: ReturnType<typeof createServer> | undefined;

  afterEach(async () => {
    if (!server) return;
    await new Promise<void>((resolve) => server!.close(() => resolve()));
    server = undefined;
  });

  it('lists publication tools and publishes through an in-memory client', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-mcp-'));
    const file = join(dir, 'notes.txt');
    await writeFile(file, 'hello');
    let created = false;

    const apiUrl = await startMockApi(async (req, res, body) => {
      if (req.method === 'POST' && req.url === '/v1/publications') {
        created = true;
        expect(req.headers.authorization).toBe('Bearer tok_mcp');
        expect(JSON.parse(body.toString())).toMatchObject({ kind: 'file', filename: 'notes.txt' });
        return json(res, 200, {
          id: 'pub_1',
          slug: 'notes',
          url: 'https://p-notes.fastsha.red',
          version: 1,
          upload: { url: `${apiUrl}/r2/pub`, method: 'PUT', headers: {} },
        });
      }
      if (req.method === 'PUT' && req.url === '/r2/pub') {
        expect(body.toString()).toBe('hello');
        res.writeHead(200);
        res.end();
        return;
      }
      if (req.method === 'POST' && req.url === '/v1/publications/pub_1/versions/1/complete') {
        return json(res, 200, {
          url: 'https://p-notes.fastsha.red',
          version: 1,
          fileCount: 1,
          totalBytes: body.length,
        });
      }
      return json(res, 404, {});
    });

    const mcp = createPublicationMcpServer({
      api: new FastSharedApi({ apiBaseUrl: apiUrl }),
      deviceToken: 'tok_mcp',
      cwd: dir,
      pollIntervalMs: 20,
      pollTimeoutMs: 1000,
    });
    const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
    await mcp.connect(serverTransport);
    const client = new Client({ name: 'fastshared-test', version: '0.0.0' });
    await client.connect(clientTransport);

    try {
      const listed = await client.listTools();
      expect(listed.tools.map((tool) => tool.name).sort()).toEqual(['list', 'opens', 'publish', 'revoke', 'update']);
      const result = await client.callTool({ name: 'publish', arguments: { path: file, title: 'Notes' } });
      expect(result.isError).not.toBe(true);
      const text = textContent(result.content);
      expect(JSON.parse(text)).toMatchObject({
        id: 'pub_1',
        slug: 'notes',
        url: 'https://p-notes.fastsha.red',
        version: 1,
        fileCount: 1,
      });
      expect(created).toBe(true);
    } finally {
      await client.close();
      await mcp.close();
    }
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

function textContent(content: ReadonlyArray<{ type: string; text?: string }>): string {
  const block = content.find((item) => item.type === 'text');
  if (!block?.text) throw new Error('missing text content');
  return block.text;
}
