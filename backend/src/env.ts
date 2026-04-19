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
}

export interface AppVars {
  requestId: string;
  deviceId?: string;
  startedAt: number;
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
