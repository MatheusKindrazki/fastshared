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
    // lastmod = build time, evaluated when this config loads. Truthful for a
    // static site: every deploy regenerates every page, so the build stamp is
    // the last time the served HTML for a URL actually changed.
    sitemap({ lastmod: new Date() }),
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
