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
            SHORT_LINK_HOST: 'https://fsh.dev',
            PUBLIC_API_HOST: 'https://api.test.fastshared.app',
            DEVICE_TOKEN_PEPPER: 'test-pepper-of-sufficient-length-0000',
            APP_ENV: 'test',
          },
        },
      },
    },
    alias: {
      '~': new URL('./src/', import.meta.url).pathname,
    },
  },
});
