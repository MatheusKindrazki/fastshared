// Browser-renderable user content needs a sandbox even when served inline.
// Strip parameters so values such as text/html; charset=utf-8 are covered.
export function isActiveContentType(contentType: string): boolean {
  const mime = contentType.split(';', 1)[0]?.trim().toLowerCase() ?? '';
  return (
    mime.startsWith('text/') ||
    mime === 'image/svg+xml' ||
    mime === 'application/xml' ||
    mime === 'application/xhtml+xml' ||
    mime.endsWith('+xml') ||
    mime === 'application/javascript' ||
    mime === 'application/ecmascript'
  );
}
