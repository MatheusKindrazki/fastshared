import type { Env } from '~/env';
import { log } from '~/lib/logger';

export interface EmailSender {
  sendMagicLink(to: string, url: string): Promise<void>;
}

export function emailSender(env: Env): EmailSender | null {
  if (env.EMAIL_SENDER === 'log' && (env.APP_ENV === 'dev' || env.APP_ENV === 'test')) {
    return { sendMagicLink: async (to, url) => log.info({ msg: 'magic_link_dev', to, url }) };
  }
  if (!env.RESEND_API_KEY || !env.EMAIL_FROM) return null;
  return {
    async sendMagicLink(to, url) {
      const response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          authorization: `Bearer ${env.RESEND_API_KEY}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          from: env.EMAIL_FROM,
          to: [to],
          subject: 'Sign in to FastShared',
          text: `Open this link to sign in to FastShared. It expires in 15 minutes.\n\n${url}`,
        }),
      });
      if (!response.ok) throw new Error(`Resend returned ${response.status}`);
    },
  };
}
