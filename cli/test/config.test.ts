import { mkdtemp, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { describe, expect, it } from 'vitest';
import { loadConfig, resolveConfigPath, saveConfig } from '../src/config.js';

describe('config', () => {
  it('resolves env override before XDG default', () => {
    expect(resolveConfigPath({ FASTSHARED_CONFIG: '/tmp/fastshared.json' }, '/home/me')).toBe(
      '/tmp/fastshared.json',
    );
    expect(resolveConfigPath({ XDG_CONFIG_HOME: '/cfg' }, '/home/me')).toBe(
      '/cfg/fastshared/config.json',
    );
  });

  it('saves and loads config with 0600 file mode', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'fastshared-config-test-'));
    const path = join(dir, 'nested', 'config.json');
    await saveConfig(path, {
      version: 1,
      deviceId: 'dev_1',
      deviceToken: 'tok_1',
      apiBaseUrl: 'https://api.test',
    });

    await expect(loadConfig(path)).resolves.toEqual({
      version: 1,
      deviceId: 'dev_1',
      deviceToken: 'tok_1',
      apiBaseUrl: 'https://api.test',
    });
    expect((await stat(path)).mode & 0o777).toBe(0o600);
  });
});
