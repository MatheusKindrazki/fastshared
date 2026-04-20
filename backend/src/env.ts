import { z } from 'zod';

export interface Env {
  DATABASE_URL: string;
  R2: R2Bucket;
  RATE_LIMIT: KVNamespace;
  R2_ACCOUNT_ID: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  R2_BUCKET_NAME: string;
  SHORT_LINK_HOST: string;
  PUBLIC_API_HOST: string;
  DEVICE_TOKEN_PEPPER: string;
  APP_ENV: string;
  // App Store Server API credentials. The three APP_STORE_CONNECT_* values
  // come from an ASC API Key (In-App Purchase access). APPLE_BUNDLE_ID is a
  // public var in wrangler.toml — the others are Wrangler secrets.
  APP_STORE_CONNECT_KEY_ID: string;
  APP_STORE_CONNECT_ISSUER_ID: string;
  APP_STORE_CONNECT_P8_KEY_BASE64: string;
  APPLE_BUNDLE_ID: string;
  // Comma-separated Apple User IDs (the `sub` claim on the identity token)
  // that should bypass the paywall and always resolve as Pro/lifetime.
  // Optional — absent/empty means no devs overridden. Public (it's just an
  // opaque Apple sub, not a credential); kept in `[vars]` for traceability.
  DEV_PRO_APPLE_USER_IDS?: string;
}

export interface AppVars {
  requestId: string;
  deviceId?: string;
  startedAt: number;
  // Set by rateLimitFreeTier when retention policy exceeded the Free cap and
  // was silently clamped to `oneDay`. Route handlers read this to echo a
  // `{ retentionClamped: true, clampedTo: 'oneDay' }` flag.
  freeTierClampedRetention?: boolean;
}

export type AppBindings = { Bindings: Env; Variables: AppVars };

export const envSchema = z.object({
  DATABASE_URL: z.string().min(1, 'DATABASE_URL secret is required'),
  R2_ACCOUNT_ID: z.string().min(1),
  R2_ACCESS_KEY_ID: z.string().min(1),
  R2_SECRET_ACCESS_KEY: z.string().min(1),
  R2_BUCKET_NAME: z.string().min(1),
  SHORT_LINK_HOST: z.string().url(),
  PUBLIC_API_HOST: z.string().url(),
  DEVICE_TOKEN_PEPPER: z.string().min(16, 'DEVICE_TOKEN_PEPPER must be at least 16 chars'),
  APP_ENV: z.string().min(1),
  APP_STORE_CONNECT_KEY_ID: z.string().min(1),
  APP_STORE_CONNECT_ISSUER_ID: z.string().min(1),
  APP_STORE_CONNECT_P8_KEY_BASE64: z
    .string()
    .min(20, 'APP_STORE_CONNECT_P8_KEY_BASE64 must be a base64 PKCS8 private key'),
  APPLE_BUNDLE_ID: z.string().min(1),
});

export type ValidatedEnv = z.infer<typeof envSchema>;

export function assertEnv(env: Env): ValidatedEnv {
  const parsed = envSchema.safeParse(env);
  if (!parsed.success) {
    throw new Error(
      `Environment misconfigured: ${parsed.error.issues
        .map((i) => `${i.path.join('.')}: ${i.message}`)
        .join('; ')}`,
    );
  }
  return parsed.data;
}
