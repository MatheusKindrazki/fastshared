// Minimal RFC 7233 Range parser. Single-range only — multi-range is allowed to
// be ignored (we return `none`) and callers fall back to a 200 with the full
// entity. Malformed headers also degrade to `none`; we never throw.

export type ParsedRange =
  | { kind: 'none' }
  | { kind: 'range'; offset: number; length: number }
  | { kind: 'suffix'; suffix: number }
  | { kind: 'unsatisfiable' };

const PREFIX = 'bytes=';

export function parseRangeHeader(header: string | null, totalSize: number): ParsedRange {
  if (!header) return { kind: 'none' };
  if (!Number.isFinite(totalSize) || totalSize < 0) return { kind: 'none' };

  const lower = header.trim().toLowerCase();
  if (!lower.startsWith(PREFIX)) return { kind: 'none' };
  const spec = lower.slice(PREFIX.length).trim();
  // Multi-range: `bytes=0-99,200-299`. Ignore per RFC 7233 §3.1.
  if (spec.includes(',')) return { kind: 'none' };

  const dashIdx = spec.indexOf('-');
  if (dashIdx < 0) return { kind: 'none' };

  const firstRaw = spec.slice(0, dashIdx).trim();
  const lastRaw = spec.slice(dashIdx + 1).trim();

  if (firstRaw === '') {
    // Suffix range: `bytes=-500` — last N bytes.
    if (!/^\d+$/.test(lastRaw)) return { kind: 'none' };
    const suffix = Number(lastRaw);
    if (!Number.isSafeInteger(suffix) || suffix === 0) return { kind: 'none' };
    if (totalSize === 0) return { kind: 'unsatisfiable' };
    return { kind: 'suffix', suffix: Math.min(suffix, totalSize) };
  }

  if (!/^\d+$/.test(firstRaw)) return { kind: 'none' };
  const start = Number(firstRaw);
  if (!Number.isSafeInteger(start)) return { kind: 'none' };

  if (lastRaw === '') {
    // Open range: `bytes=500-`.
    if (start >= totalSize) return { kind: 'unsatisfiable' };
    return { kind: 'range', offset: start, length: totalSize - start };
  }

  if (!/^\d+$/.test(lastRaw)) return { kind: 'none' };
  const end = Number(lastRaw);
  if (!Number.isSafeInteger(end)) return { kind: 'none' };
  if (end < start) return { kind: 'none' };
  if (start >= totalSize) return { kind: 'unsatisfiable' };
  const clampedEnd = Math.min(end, totalSize - 1);
  return { kind: 'range', offset: start, length: clampedEnd - start + 1 };
}
