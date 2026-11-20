import { SignJWT, importPKCS8 } from 'jose';
import type { Db } from '~/db/client';
import type { Env } from '~/env';
import { clearDevicePushToken, findDeviceById, listUserDevices } from '~/services/devices';
import type { Device } from '~/db/schema';
import { log } from '~/lib/logger';

export interface SendLinkOpenedNotificationArgs {
  env: Env;
  db: Db;
  deviceId: string;
  token: string;
  filename?: string | null;
  shortUrl: string;
}

const MAX_ALERT_DEVICES = 10;

// Sends the open alert to every push-capable device of the owner's account,
// not only the device that created the link. A publication made from the CLI
// or the web has no push token of its own; the owner's iPhone is the one that
// should ping. Returns true when at least one device accepted the alert.
export async function sendLinkOpenedNotification(
  args: SendLinkOpenedNotificationArgs,
): Promise<boolean> {
  const config = apnsConfig(args.env);
  if (!config) {
    log.warn({ msg: 'apns_not_configured' });
    return false;
  }

  const origin = await findDeviceById(args.db, args.deviceId);
  if (!origin) return false;
  const candidates = origin.userId ? await listUserDevices(args.db, origin.userId) : [];
  const seen = new Set<string>();
  const targets = [origin, ...candidates]
    .filter((d) => d.apnsToken && d.apnsEnvironment)
    .filter((d) => (seen.has(d.id) ? false : (seen.add(d.id), true)))
    .slice(0, MAX_ALERT_DEVICES);
  if (targets.length === 0) return false;

  const jwt = await providerToken(config);
  const results = await Promise.all(
    targets.map((d) => sendToDevice(args, config, jwt, d).catch(() => false)),
  );
  return results.some(Boolean);
}

async function sendToDevice(
  args: SendLinkOpenedNotificationArgs,
  config: APNSConfig,
  jwt: string,
  target: Device,
): Promise<boolean> {
  const endpoint =
    target.apnsEnvironment === 'development'
      ? `https://api.sandbox.push.apple.com/3/device/${target.apnsToken}`
      : `https://api.push.apple.com/3/device/${target.apnsToken}`;

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

  if (response.ok) return true;

  const detail = await safeText(response);
  log.warn({
    msg: 'apns_send_failed',
    status: response.status,
    reason: detail,
    deviceId: target.id,
    token: args.token,
  });

  if (response.status === 410 || /BadDeviceToken|Unregistered/i.test(detail)) {
    await clearDevicePushToken(args.db, target.id);
  }
  return false;
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

export function linkOpenedAlertBody(filename?: string | null): string {
  const clean = filename?.trim();
  if (!clean) return 'Your link was opened in a browser';
  const clipped = clean.length > 80 ? `${clean.slice(0, 77)}...` : clean;
  return `"${clipped}" was opened in a browser`;
}

function notificationBody(filename?: string | null): string {
  return linkOpenedAlertBody(filename);
}

async function safeText(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch {
    return '';
  }
}
