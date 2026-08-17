// @ts-check
import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';
import sitemap from '@astrojs/sitemap';

// https://astro.build/config
export default defineConfig({
  site: 'https://fastsha.red',
  // 'always' matches what Cloudflare Pages actually serves: the build emits
  // dist/<page>/index.html and the platform 308s /<page> to /<page>/. With 'never',
  // rel=canonical and every sitemap <loc> named the redirecting form, so five of six
  // pages pointed their canonical at a URL that redirects to themselves.
  trailingSlash: 'always',
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
