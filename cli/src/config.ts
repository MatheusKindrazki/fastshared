import { dirname, join } from 'node:path';
import { homedir } from 'node:os';
import { mkdir, readFile, rename, rm, writeFile, chmod } from 'node:fs/promises';

export interface CliConfig {
  version: 1;
  deviceId?: string;
  deviceToken?: string;
  apiBaseUrl?: string;
}

export function resolveConfigPath(
  env: NodeJS.ProcessEnv = process.env,
  home: string = homedir(),
): string {
  if (env.FASTSHARED_CONFIG) return env.FASTSHARED_CONFIG;
  const base = env.XDG_CONFIG_HOME || join(home, '.config');
  return join(base, 'fastshared', 'config.json');
}

export async function loadConfig(path: string): Promise<Partial<CliConfig>> {
  try {
    const raw = await readFile(path, 'utf8');
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== 'object') return {};
    const obj = parsed as Record<string, unknown>;
    return {
      version: 1,
      ...(typeof obj.deviceId === 'string' ? { deviceId: obj.deviceId } : {}),
      ...(typeof obj.deviceToken === 'string' ? { deviceToken: obj.deviceToken } : {}),
      ...(typeof obj.apiBaseUrl === 'string' ? { apiBaseUrl: obj.apiBaseUrl } : {}),
    };
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') return {};
    throw err;
  }
}

export async function saveConfig(path: string, config: CliConfig): Promise<void> {
  const dir = dirname(path);
  await mkdir(dir, { recursive: true, mode: 0o700 });
  const tmp = `${path}.${process.pid}.${Date.now()}.tmp`;
  try {
    await writeFile(tmp, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
    await chmod(tmp, 0o600);
    await rename(tmp, path);
    await chmod(path, 0o600);
  } catch (err) {
    await rm(tmp, { force: true }).catch(() => undefined);
    throw err;
  }
}
