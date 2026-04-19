// RFC 6266 §5 two-form Content-Disposition for attachments. The ASCII fallback
// handles ancient clients; filename* uses RFC 5987 percent-encoding so UTF-8
// filenames survive through any standards-compliant HTTP client.

export function contentDispositionAttachment(filename: string): string {
  const safe = filename.length > 0 ? filename : 'download';
  const asciiFallback = toAsciiFallback(safe);
  const encoded = rfc5987Encode(safe);
  return `attachment; filename="${asciiFallback}"; filename*=UTF-8''${encoded}`;
}

function toAsciiFallback(name: string): string {
  // Strip anything outside printable ASCII and escape the two characters
  // (backslash, double-quote) that would break the quoted-string form.
  let out = '';
  for (const ch of name) {
    const code = ch.charCodeAt(0);
    if (code < 0x20 || code === 0x7f) continue;
    if (code > 0x7e) {
      out += '_';
      continue;
    }
    if (ch === '"' || ch === '\\') out += '\\' + ch;
    else out += ch;
  }
  return out.length > 0 ? out : 'download';
}

function rfc5987Encode(s: string): string {
  // encodeURIComponent leaves !*'() unescaped; RFC 5987 requires us to escape
  // `*` and `'` too so the token can't be mistaken for a parameter terminator.
  return encodeURIComponent(s)
    .replace(/\*/g, '%2A')
    .replace(/'/g, '%27')
    .replace(/\(/g, '%28')
    .replace(/\)/g, '%29');
}
