import type { Readable, Writable } from 'node:stream';
import { FastSharedApi, FastSharedHttpError, type UploadResult } from './api.js';
import { loadConfig, resolveConfigPath, saveConfig, type CliConfig } from './config.js';
import { servePublicationMcp } from './mcp.js';
import { CLI_VERSION, DEFAULT_API_URL, parseCommand, UsageError, usage, type CommandFlags, type ParsedCommand } from './options.js';
import {
  CommandError,
  formatOpens,
  formatPublicationList,
  formatRevocation,
  listPublications,
  publicationOpens,
  publicationPollSettings,
  publishLocalPath,
  revokePublication,
  type PublishedPublication,
} from './publish.js';
import { stageInputs } from './stage.js';

export interface CliIO {
  stdout: Writable;
  stderr: Writable;
  stdin: Readable;
  env: NodeJS.ProcessEnv;
  cwd: string;
  fetchImpl?: typeof fetch;
}

export async function runCli(
  argv: string[],
  io: CliIO = {
    stdout: process.stdout,
    stderr: process.stderr,
    stdin: process.stdin,
    env: process.env,
    cwd: process.cwd(),
  },
): Promise<number> {
  let outputJson = false;
  try {
    const command = parseCommand(argv);
    outputJson = command.outputJson;
    if (command.help) {
      io.stdout.write(usage());
      return 0;
    }
    if (command.version) {
      io.stdout.write(`${CLI_VERSION}\n`);
      return 0;
    }
    const session = await openSession(command, io);
    switch (command.command) {
      case 'upload':
        return await runUpload(command, session, io);
      case 'publish':
        return await runPublish(command, session, io);
      case 'publications':
        return await runPublications(command, session, io);
      case 'mcp':
        return await runMcp(session, io);
      default:
        return 1;
    }
  } catch (err) {
    writeError(io.stderr, err, outputJson);
    if (err instanceof UsageError || err instanceof CommandError) return err.exitCode;
    return 1;
  }
}

interface Session {
  api: FastSharedApi;
  deviceToken: string;
}

async function openSession(command: CommandFlags, io: CliIO): Promise<Session> {
  const configPath = command.configPath ?? resolveConfigPath(io.env);
  const config = await loadConfig(configPath);
  const apiBaseUrl = stripTrailingSlash(
    command.apiUrl ?? io.env.FASTSHARED_API_URL ?? config.apiBaseUrl ?? DEFAULT_API_URL,
  );
  const api = new FastSharedApi({ apiBaseUrl, ...(io.fetchImpl ? { fetchImpl: io.fetchImpl } : {}) });
  const deviceToken = await resolveDeviceToken({
    api,
    config,
    configPath,
    apiBaseUrl,
    env: io.env,
  });
  return { api, deviceToken };
}

async function runUpload(command: Extract<ParsedCommand, { command: 'upload' }>, session: Session, io: CliIO): Promise<number> {
  const staged = await stageInputs(command.inputs, {
    ...(command.name ? { name: command.name } : {}),
    stdin: io.stdin,
    cwd: io.cwd,
  });
  try {
    if (!command.quiet) {
      io.stderr.write(`Uploading ${staged.filename} (${staged.sizeBytes} bytes)...\n`);
    }
    const result = await session.api.uploadFile(
      {
        filePath: staged.filePath,
        filename: staged.filename,
        contentType: staged.contentType,
        sizeBytes: staged.sizeBytes,
        sha256: staged.sha256,
        retentionPolicy: command.retentionPolicy,
      },
      session.deviceToken,
    );
    writeUploadSuccess(io.stdout, result, command.outputJson);
    return 0;
  } finally {
    await staged.cleanup();
  }
}

async function runPublish(
  command: Extract<ParsedCommand, { command: 'publish' }>,
  session: Session,
  io: CliIO,
): Promise<number> {
  if (!command.path) throw new UsageError('publish expects one file or directory.');
  const poll = publicationPollSettings(io.env);
  const published = await publishLocalPath({
    api: session.api,
    deviceToken: session.deviceToken,
    cwd: io.cwd,
    inputPath: command.path,
    ...(command.title ? { title: command.title } : {}),
    ...(command.update ? { update: command.update } : {}),
    pollIntervalMs: poll.pollIntervalMs,
    pollTimeoutMs: poll.pollTimeoutMs,
    ...(!command.quiet ? { onProgress: (message: string) => io.stderr.write(`${message}\n`) } : {}),
  });
  writePublication(io.stdout, published, command.outputJson);
  return 0;
}

async function runPublications(
  command: Extract<ParsedCommand, { command: 'publications' }>,
  session: Session,
  io: CliIO,
): Promise<number> {
  if (command.action === 'list') {
    const items = await listPublications(session.api, session.deviceToken);
    if (command.outputJson) {
      io.stdout.write(`${JSON.stringify({ publications: items })}\n`);
    } else {
      io.stdout.write(formatPublicationList(items));
    }
    return 0;
  }
  if (!command.action || !command.target) {
    throw new UsageError('publications expects list, revoke <id|slug>, or opens <id|slug>.');
  }
  if (command.action === 'revoke') {
    const revoked = await revokePublication(session.api, session.deviceToken, command.target);
    if (command.outputJson) io.stdout.write(`${JSON.stringify(revoked)}\n`);
    else io.stdout.write(formatRevocation(revoked));
    return 0;
  }
  const opens = await publicationOpens(session.api, session.deviceToken, command.target);
  if (command.outputJson) io.stdout.write(`${JSON.stringify(opens)}\n`);
  else io.stdout.write(formatOpens(opens));
  return 0;
}

async function runMcp(session: Session, io: CliIO): Promise<number> {
  const poll = publicationPollSettings(io.env);
  await servePublicationMcp({
    api: session.api,
    deviceToken: session.deviceToken,
    cwd: io.cwd,
    pollIntervalMs: poll.pollIntervalMs,
    pollTimeoutMs: poll.pollTimeoutMs,
    onProgress: (message) => io.stderr.write(`${message}\n`),
  });
  return 0;
}

async function resolveDeviceToken(args: {
  api: FastSharedApi;
  config: Partial<CliConfig>;
  configPath: string;
  apiBaseUrl: string;
  env: NodeJS.ProcessEnv;
}): Promise<string> {
  if (args.env.FASTSHARED_DEVICE_TOKEN) return args.env.FASTSHARED_DEVICE_TOKEN;
  if (args.config.deviceToken) return args.config.deviceToken;

  const registration = await args.api.registerDevice(`fastshared-cli/${CLI_VERSION}`);
  await saveConfig(args.configPath, {
    version: 1,
    deviceId: registration.deviceId,
    deviceToken: registration.deviceToken,
    apiBaseUrl: args.apiBaseUrl,
  });
  return registration.deviceToken;
}

function writeUploadSuccess(stdout: Writable, result: UploadResult, outputJson: boolean): void {
  if (outputJson) {
    stdout.write(`${JSON.stringify(result)}\n`);
    return;
  }
  stdout.write(`${result.shortUrl}\n`);
}

function writePublication(stdout: Writable, result: PublishedPublication, outputJson: boolean): void {
  if (outputJson) {
    stdout.write(`${JSON.stringify(result)}\n`);
    return;
  }
  stdout.write(`${result.url}\n`);
}

function writeError(stderr: Writable, err: unknown, outputJson: boolean): void {
  if (err instanceof CommandError) {
    if (outputJson) {
      stderr.write(
        `${JSON.stringify({
          error: err.code ?? 'publication_error',
          detail: err.message,
          ...(err.upgradeUrl ? { upgradeUrl: err.upgradeUrl } : {}),
        })}\n`,
      );
      return;
    }
    for (const line of err.message.split('\n')) stderr.write(`fastshared: ${line}\n`);
    if (err.upgradeUrl) stderr.write(`fastshared: ${err.upgradeUrl}\n`);
    return;
  }
  if (outputJson && err instanceof FastSharedHttpError) {
    stderr.write(
      `${JSON.stringify({
        error: err.code ?? 'http_error',
        status: err.status,
        detail: err.detail ?? err.message,
        ...(err.upgradeUrl ? { upgradeUrl: err.upgradeUrl } : {}),
      })}\n`,
    );
    return;
  }
  if (err instanceof UsageError) {
    stderr.write(`${err.message}\n\n${usage()}`);
    return;
  }
  if (err instanceof FastSharedHttpError) {
    const code = err.code ? ` ${err.code}` : '';
    stderr.write(`fastshared: HTTP ${err.status}${code}: ${err.detail ?? err.message}\n`);
    return;
  }
  stderr.write(`fastshared: ${err instanceof Error ? err.message : String(err)}\n`);
}

function stripTrailingSlash(value: string): string {
  return value.replace(/\/+$/, '');
}
