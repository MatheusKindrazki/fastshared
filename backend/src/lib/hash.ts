const encoder = new TextEncoder();

function toHex(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let hex = '';
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i] ?? 0;
    hex += b.toString(16).padStart(2, '0');
  }
  return hex;
}

export async function hmacSha256Hex(key: string, message: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    encoder.encode(key),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', cryptoKey, encoder.encode(message));
  return toHex(sig);
}

export async function sha256Hex(message: string | Uint8Array): Promise<string> {
  const data: BufferSource =
    typeof message === 'string' ? encoder.encode(message) : (message as BufferSource);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return toHex(digest);
}

export function toBase64Url(bytes: Uint8Array): string {
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i] ?? 0);
  const b64 = btoa(bin);
  return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
