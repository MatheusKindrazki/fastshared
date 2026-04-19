import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config';

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: './wrangler.toml' },
        miniflare: {
          compatibilityFlags: ['nodejs_compat'],
          bindings: {
            DATABASE_URL: 'postgres://test:test@localhost/test',
            R2_ACCOUNT_ID: 'test-account',
            R2_ACCESS_KEY_ID: 'test-access-key',
            R2_SECRET_ACCESS_KEY: 'test-secret-key',
            R2_BUCKET_NAME: 'fastshared-test',
            SHORT_LINK_HOST: 'https://fastsha.red',
            PUBLIC_API_HOST: 'https://api.fastsha.red',
            DEVICE_TOKEN_PEPPER: 'test-pepper-of-sufficient-length-0000',
            APP_ENV: 'test',
            // IAP + App Store Server API test fixtures. Tests that exercise
            // the JWS/JWT path generate their own ES256 keypair at runtime and
            // override the p8 via test env; this placeholder just satisfies
            // the envSchema so first-request validation passes.
            APP_STORE_CONNECT_KEY_ID: 'TESTKEYID0',
            APP_STORE_CONNECT_ISSUER_ID: '00000000-0000-0000-0000-000000000000',
            APP_STORE_CONNECT_P8_KEY_BASE64:
              'dGVzdC1wOC1wbGFjZWhvbGRlci1iYXNlNjQtZm9yLWVudi12YWxpZGF0aW9u',
            APPLE_BUNDLE_ID: 'red.fastsha.FastShared',
          },
        },
      },
    },
    alias: {
      '~': new URL('./src/', import.meta.url).pathname,
    },
  },
});
