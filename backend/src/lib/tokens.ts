import { toBase62 } from '~/lib/base62';

export const TOKEN_LENGTH = 22;

// 22 base62 chars ≈ 131 bits of entropy. 32 random bytes oversample heavily so
// even pathologically leading-zero inputs still produce >=22 chars after encode.
export function generateToken(length: number = TOKEN_LENGTH): string {
  if (length < 1) throw new Error('token length must be >= 1');
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  const encoded = toBase62(bytes);
  if (encoded.length >= length) return encoded.slice(0, length);
  // Virtually unreachable (would require most of 32 bytes to be zero); pad
  // with a fresh draw just in case.
  return (encoded + generateToken(length - encoded.length)).slice(0, length);
}
