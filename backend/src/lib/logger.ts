type Fields = Record<string, unknown>;

function emit(level: 'info' | 'warn' | 'error' | 'debug', fields: Fields): void {
  const line = { level, ts: new Date().toISOString(), ...fields };
  const serialized = JSON.stringify(line);
  if (level === 'error') console.error(serialized);
  else if (level === 'warn') console.warn(serialized);
  else console.log(serialized);
}

export const log = {
  info: (fields: Fields) => emit('info', fields),
  warn: (fields: Fields) => emit('warn', fields),
  error: (fields: Fields) => emit('error', fields),
  debug: (fields: Fields) => emit('debug', fields),
};
