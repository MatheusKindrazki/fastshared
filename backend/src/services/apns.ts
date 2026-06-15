import { SignJWT, importPKCS8 } from 'jose';
import type { Db } from '~/db/client';
import type { Env } from '~/env';
import { clearDevicePushToken, findDeviceById } from '~/services/devices';
import { log } from '~/lib/logger';

export interface SendLinkOpenedNotificationArgs {
  env: Env;
  db: Db;
  deviceId: string;
  token: string;
  filename?: string | null;
  shortUrl: string;
}

export async function sendLinkOpenedNotification(
  args: SendLinkOpenedNotificationArgs,
): Promise<void> {
  const config = apnsConfig(args.env);
  if (!config) {
    log.warn({ msg: 'apns_not_configured' });
    return;
  }

  const device = await findDeviceById(args.db, args.deviceId);
  if (!device?.apnsToken || !device.apnsEnvironment) return;

  const jwt = await providerToken(config);
  const endpoint =
    device.apnsEnvironment === 'development'
      ? `https://api.sandbox.push.apple.com/3/device/${device.apnsToken}`
      : `https://api.push.apple.com/3/device/${device.apnsToken}`;

  const payload = {
    aps: {
      alert: {
        title: 'FastShared',
        body: notificationBody(args.filename),
      },
      sound: 'default',
      'thread-id': `link-open:${args.token}`,
    },
    kind: 'link_opened',
    token: args.token,
    url: args.shortUrl,
  };

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      authorization: `bearer ${jwt}`,
      'apns-topic': config.topic,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  if (response.ok) return;

  const detail = await safeText(response);
  log.warn({
    msg: 'apns_send_failed',
    status: response.status,
    reason: detail,
    deviceId: args.deviceId,
    token: args.token,
  });

  if (response.status === 410 || /BadDeviceToken|Unregistered/i.test(detail)) {
    await clearDevicePushToken(args.db, args.deviceId);
  }
}

interface APNSConfig {
  keyId: string;
  teamId: string;
  privateKeyPem: string;
  topic: string;
}

function apnsConfig(env: Env): APNSConfig | null {
  if (!env.APNS_KEY_ID || !env.APNS_TEAM_ID || !env.APNS_P8_KEY_BASE64) return null;
  return {
    keyId: env.APNS_KEY_ID,
    teamId: env.APNS_TEAM_ID,
    privateKeyPem: decodeBase64(env.APNS_P8_KEY_BASE64),
    topic: env.APNS_TOPIC ?? env.APPLE_BUNDLE_ID,
  };
}

async function providerToken(config: APNSConfig): Promise<string> {
  const key = await importPKCS8(config.privateKeyPem, 'ES256');
  return new SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: config.keyId })
    .setIssuer(config.teamId)
    .setIssuedAt()
    .sign(key);
}

function decodeBase64(value: string): string {
  const binary = atob(value);
  const bytes = Uint8Array.from(binary, (ch) => ch.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

function notificationBody(filename?: string | null): string {
  const clean = filename?.trim();
  if (!clean) return 'Your shared link was opened.';
  const clipped = clean.length > 80 ? `${clean.slice(0, 77)}...` : clean;
  return `"${clipped}" was opened.`;
}

async function safeText(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch {
    return '';
  }
}
