import { describe, it, expect } from 'vitest';
import { linkOpenedAlertBody } from '~/services/apns';

describe('link opened alert copy', () => {
  it('names the file that was opened in a browser', () => {
    expect(linkOpenedAlertBody('photo.jpg')).toBe('"photo.jpg" was opened in a browser');
  });

  it('uses the file count for a multi-file bundle', () => {
    expect(linkOpenedAlertBody('3 files')).toBe('"3 files" was opened in a browser');
  });

  it('clips a name longer than 80 characters', () => {
    const name = `${'a'.repeat(81)}.bin`;
    expect(linkOpenedAlertBody(name)).toBe(`"${'a'.repeat(77)}..." was opened in a browser`);
  });

  it('keeps a name of exactly 80 characters', () => {
    const name = 'b'.repeat(80);
    expect(linkOpenedAlertBody(name)).toBe(`"${name}" was opened in a browser`);
  });

  it('falls back when the link has no name', () => {
    expect(linkOpenedAlertBody()).toBe('Your link was opened in a browser');
    expect(linkOpenedAlertBody(null)).toBe('Your link was opened in a browser');
    expect(linkOpenedAlertBody('   ')).toBe('Your link was opened in a browser');
  });

  it('does not call the opener a client', () => {
    for (const body of [
      linkOpenedAlertBody('photo.jpg'),
      linkOpenedAlertBody('3 files'),
      linkOpenedAlertBody(),
    ]) {
      expect(body.toLowerCase()).not.toContain('client');
    }
  });
});
