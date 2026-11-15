import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import type { FastSharedApi } from './api.js';
import { CLI_VERSION } from './options.js';
import { listPublications, publicationOpens, publishLocalPath, revokePublication } from './publish.js';

export interface PublicationMcpRuntime {
  api: FastSharedApi;
  deviceToken: string;
  cwd: string;
  pollIntervalMs: number;
  pollTimeoutMs: number;
  onProgress?: (message: string) => void;
}

const publishShape = {
  path: z.string().describe('Local file or directory to publish'),
  title: z.string().optional().describe('Optional publication title'),
};

const idShape = {
  id: z.string().describe('Publication id or slug'),
};

export function createPublicationMcpServer(runtime: PublicationMcpRuntime): McpServer {
  const server = new McpServer({ name: 'fastshared', version: CLI_VERSION });

  server.registerTool(
    'publish',
    {
      description:
        'Publish a file or folder to a new stable URL. A folder or HTML file becomes a site, a PDF stays a PDF, and any other file stays a file. Requires the publications API.',
      inputSchema: publishShape,
    },
    async ({ path, title }) =>
      runTool(() =>
        publishLocalPath({
          api: runtime.api,
          deviceToken: runtime.deviceToken,
          cwd: runtime.cwd,
          inputPath: path,
          ...(title !== undefined ? { title } : {}),
          pollIntervalMs: runtime.pollIntervalMs,
          pollTimeoutMs: runtime.pollTimeoutMs,
          ...(runtime.onProgress ? { onProgress: runtime.onProgress } : {}),
        }),
      ),
  );

  server.registerTool(
    'update',
    {
      description: 'Replace a publication and keep its URL. Pro only. Requires the publications API.',
      inputSchema: {
        ...idShape,
        ...publishShape,
      },
    },
    async ({ id, path, title }) =>
      runTool(() =>
        publishLocalPath({
          api: runtime.api,
          deviceToken: runtime.deviceToken,
          cwd: runtime.cwd,
          inputPath: path,
          update: id,
          ...(title !== undefined ? { title } : {}),
          pollIntervalMs: runtime.pollIntervalMs,
          pollTimeoutMs: runtime.pollTimeoutMs,
          ...(runtime.onProgress ? { onProgress: runtime.onProgress } : {}),
        }),
      ),
  );

  server.registerTool(
    'revoke',
    {
      description: 'Revoke a publication so its URL stops serving. Requires the publications API.',
      inputSchema: idShape,
    },
    async ({ id }) => runTool(() => revokePublication(runtime.api, runtime.deviceToken, id)),
  );

  server.registerTool(
    'list',
    {
      description:
        'List your publications with status, version, and opens in the last 7 days. Requires the publications API.',
      inputSchema: {},
    },
    async () => runTool(async () => ({ publications: await listPublications(runtime.api, runtime.deviceToken) })),
  );

  server.registerTool(
    'opens',
    {
      description: 'Show open counts per version for one publication. Requires the publications API.',
      inputSchema: idShape,
    },
    async ({ id }) => runTool(() => publicationOpens(runtime.api, runtime.deviceToken, id)),
  );

  return server;
}

export async function servePublicationMcp(runtime: PublicationMcpRuntime): Promise<void> {
  const server = createPublicationMcpServer(runtime);
  const transport = new StdioServerTransport();
  await new Promise<void>((resolve, reject) => {
    transport.onclose = () => resolve();
    server.connect(transport).catch(reject);
  });
}

async function runTool(work: () => Promise<unknown>): Promise<{
  content: Array<{ type: 'text'; text: string }>;
  isError?: boolean;
}> {
  try {
    const value = await work();
    return { content: [{ type: 'text', text: JSON.stringify(value) }] };
  } catch (err) {
    return {
      isError: true,
      content: [{ type: 'text', text: err instanceof Error ? err.message : String(err) }],
    };
  }
}
