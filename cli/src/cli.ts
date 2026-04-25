import type { Readable, Writable } from 'node:stream';
import { loadConfig, resolveConfigPath, saveConfig, type CliConfig } from './config.js';
import { FastSharedApi, FastSharedHttpError, type UploadResult } from './api.js';
import { CLI_VERSION, DEFAULT_API_URL, parseArgs, UsageError, usage } from './options.js';
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
    const options = parseArgs(argv);
    outputJson = options.outputJson;
    if (options.help) {
      io.stdout.write(usage());
      return 0;
    }
    if (options.version) {
      io.stdout.write(`${CLI_VERSION}\n`);
      return 0;
    }

    const configPath = options.configPath ?? resolveConfigPath(io.env);
    const config = await loadConfig(configPath);
    const apiBaseUrl = stripTrailingSlash(
      options.apiUrl ?? io.env.FASTSHARED_API_URL ?? config.apiBaseUrl ?? DEFAULT_API_URL,
    );
    const api = new FastSharedApi({ apiBaseUrl, ...(io.fetchImpl ? { fetchImpl: io.fetchImpl } : {}) });
    const deviceToken = await resolveDeviceToken({
      api,
      config,
      configPath,
      apiBaseUrl,
      env: io.env,
    });

    const staged = await stageInputs(options.inputs, {
      ...(options.name ? { name: options.name } : {}),
      stdin: io.stdin,
      cwd: io.cwd,
    });
    try {
      if (!options.quiet) {
        io.stderr.write(`Uploading ${staged.filename} (${staged.sizeBytes} bytes)...\n`);
      }
      const result = await api.uploadFile(
        {
          filePath: staged.filePath,
          filename: staged.filename,
          contentType: staged.contentType,
          sizeBytes: staged.sizeBytes,
          sha256: staged.sha256,
          retentionPolicy: options.retentionPolicy,
        },
        deviceToken,
      );
      writeSuccess(io.stdout, result, outputJson);
      return 0;
    } finally {
      await staged.cleanup();
    }
  } catch (err) {
    writeError(io.stderr, err, outputJson);
    return err instanceof UsageError ? err.exitCode : 1;
  }
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

function writeSuccess(stdout: Writable, result: UploadResult, outputJson: boolean): void {
  if (outputJson) {
    stdout.write(`${JSON.stringify(result)}\n`);
    return;
  }
  stdout.write(`${result.shortUrl}\n`);
}

function writeError(stderr: Writable, err: unknown, outputJson: boolean): void {
  if (outputJson && err instanceof FastSharedHttpError) {
    stderr.write(
      `${JSON.stringify({
        error: err.code ?? 'http_error',
        status: err.status,
        detail: err.detail ?? err.message,
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
