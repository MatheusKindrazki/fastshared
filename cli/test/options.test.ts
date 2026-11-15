import { describe, expect, it } from 'vitest';
import { parseArgs, parseCommand, parseTtl, UsageError } from '../src/options.js';

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

  it('keeps a file path on the temporary upload command', () => {
    expect(parseCommand(['notes.txt', '--ttl', '1d']).command).toBe('upload');
  });

  it('parses publication commands', () => {
    expect(parseCommand(['--json', 'publish', './site', '--title', 'Notes', '--update', 'notes'])).toMatchObject({
      command: 'publish',
      path: './site',
      title: 'Notes',
      update: 'notes',
      outputJson: true,
    });
    expect(parseCommand(['publications', 'list', '--json'])).toMatchObject({
      command: 'publications',
      action: 'list',
      outputJson: true,
    });
    expect(parseCommand(['publications', 'revoke', 'notes'])).toMatchObject({
      command: 'publications',
      action: 'revoke',
      target: 'notes',
    });
    expect(parseCommand(['publications', 'opens', 'pub_1'])).toMatchObject({
      command: 'publications',
      action: 'opens',
      target: 'pub_1',
    });
    expect(parseCommand(['mcp']).command).toBe('mcp');
  });

  it('rejects a publication id with a slash', () => {
    expect(() => parseCommand(['publications', 'revoke', 'a/b'])).toThrow(UsageError);
  });
});
