const MB = 1024 * 1024;
const GB = 1024 * MB;

export const SIZE_LIMITS = {
  image: 50 * MB,
  video: 2 * GB,
  doc: 100 * MB,
  other: 100 * MB,
} as const;

export type SizeCategory = keyof typeof SIZE_LIMITS;

const DOC_TYPES = new Set([
  'application/pdf',
  'application/zip',
  'application/x-zip-compressed',
  'application/json',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'text/plain',
  'text/csv',
  'text/markdown',
]);

export function categorize(contentType: string): SizeCategory {
  const ct = contentType.toLowerCase();
  if (ct.startsWith('image/')) return 'image';
  if (ct.startsWith('video/')) return 'video';
  if (DOC_TYPES.has(ct) || ct.startsWith('text/')) return 'doc';
  return 'other';
}

export function resolveSizeLimit(contentType: string): number {
  return SIZE_LIMITS[categorize(contentType)];
}

export const ALLOWED_CONTENT_TYPE_PREFIXES = ['image/', 'video/', 'audio/', 'text/'];

export function isAllowedContentType(contentType: string): boolean {
  const ct = contentType.toLowerCase();
  if (ALLOWED_CONTENT_TYPE_PREFIXES.some((p) => ct.startsWith(p))) return true;
  if (DOC_TYPES.has(ct)) return true;
  if (ct === 'application/octet-stream') return true;
  return false;
}
