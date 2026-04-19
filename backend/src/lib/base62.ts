const ALPHABET = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

export function toBase62(bytes: Uint8Array): string {
  if (bytes.length === 0) return '';
  // Convert big-endian byte sequence into base62 via repeated division.
  const digits = Array.from(bytes);
  const out: number[] = [];
  let leadingZeros = 0;
  for (const b of digits) {
    if (b === 0) leadingZeros += 1;
    else break;
  }
  let input = digits.slice();
  while (input.length > 0 && !(input.length === 1 && input[0] === 0)) {
    let carry = 0;
    const next: number[] = [];
    for (const d of input) {
      const cur = (carry << 8) + d;
      const q = Math.floor(cur / 62);
      carry = cur - q * 62;
      if (next.length > 0 || q > 0) next.push(q);
    }
    out.push(carry);
    input = next;
  }
  let result = '';
  for (let i = 0; i < leadingZeros; i++) result += ALPHABET[0];
  for (let i = out.length - 1; i >= 0; i--) {
    const idx = out[i] ?? 0;
    result += ALPHABET[idx];
  }
  return result === '' ? (ALPHABET[0] ?? '0') : result;
}
