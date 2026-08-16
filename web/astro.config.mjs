// @ts-check
import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';
import sitemap from '@astrojs/sitemap';

// https://astro.build/config
export default defineConfig({
  site: 'https://fastsha.red',
  trailingSlash: 'never',
  output: 'static',
  integrations: [
    tailwind({ applyBaseStyles: false }),
    sitemap(),
  ],
  build: {
    inlineStylesheets: 'auto',
  },
  compressHTML: true,
  server: {
    host: true,
    port: 4321,
  },
});
