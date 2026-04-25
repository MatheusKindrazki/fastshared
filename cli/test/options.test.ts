import { describe, expect, it } from 'vitest';
import { parseArgs, parseTtl, UsageError } from '../src/options.js';

describe('options', () => {
  it('maps ttl presets to backend retention policies', () => {
    expect(parseTtl(undefined)).toBe('oneHour');
    expect(parseTtl('60s')).toBe('oneMinute');
    expect(parseTtl('1h')).toBe('oneHour');
    expect(parseTtl('1d')).toBe('oneDay');
    expect(parseTtl('1w')).toBe('oneWeek');
    expect(parseTtl('30d')).toBe('oneMonth');
  });

  it('parses upload command options and inputs', () => {
    expect(
      parseArgs([
        'upload',
        '--ttl',
        '60s',
        '--json',
        '--quiet',
        '--api-url=https://api.example.test/',
        '--config',
        '/tmp/cfg.json',
        '--name',
        'trace.txt',
        '-',
      ]),
    ).toEqual({
      inputs: ['-'],
      retentionPolicy: 'oneMinute',
      outputJson: true,
      quiet: true,
      help: false,
      version: false,
      apiUrl: 'https://api.example.test',
      configPath: '/tmp/cfg.json',
      name: 'trace.txt',
    });
  });

  it('rejects missing input', () => {
    expect(() => parseArgs([])).toThrow(UsageError);
  });
});
