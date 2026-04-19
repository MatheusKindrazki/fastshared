import { generateToken } from '~/lib/tokens';

export function newId(): string {
  return crypto.randomUUID();
}

export function newSlug(length = 22): string {
  return generateToken(length);
}
