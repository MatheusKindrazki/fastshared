type Fields = Record<string, unknown>;

function emit(level: 'info' | 'warn' | 'error' | 'debug', fields: Fields): void {
  const line = { level, ts: new Date().toISOString(), ...(redact(fields) as Fields) };
  const serialized = JSON.stringify(line);
  if (level === 'error') console.error(serialized);
  else if (level === 'warn') console.warn(serialized);
  else console.log(serialized);
}

function redact(value: unknown, key = ''): unknown {
  if (isSensitiveKey(key)) {
    if (value === null || value === undefined) return value;
    return '[redacted]';
  }
  if (Array.isArray(value)) return value.map((item) => redact(item));
  if (!value || typeof value !== 'object') return value;
  if (value instanceof Date) return value.toISOString();
  const out: Record<string, unknown> = {};
  for (const [childKey, childValue] of Object.entries(value as Record<string, unknown>)) {
    out[childKey] = redact(childValue, childKey);
  }
  return out;
}

function isSensitiveKey(key: string): boolean {
  const normalized = key.replace(/[-_]/g, '').toLowerCase();
  return (
    normalized === 'authorization' ||
    normalized === 'bearer' ||
    normalized.endsWith('token') ||
    normalized.endsWith('deviceid') ||
    normalized.endsWith('assetid') ||
    normalized.endsWith('transactionid') ||
    normalized === 'storagekey'
  );
}

export const log = {
  info: (fields: Fields) => emit('info', fields),
  warn: (fields: Fields) => emit('warn', fields),
  error: (fields: Fields) => emit('error', fields),
  debug: (fields: Fields) => emit('debug', fields),
};
