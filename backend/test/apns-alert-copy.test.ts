import { describe, it, expect } from 'vitest';
import { linkOpenedAlertBody } from '~/services/apns';

describe('link opened alert copy', () => {
  it('says the link was opened in a browser', () => {
    expect(linkOpenedAlertBody()).toBe('Opened in a browser');
  });
});
