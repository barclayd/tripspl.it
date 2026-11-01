import { defineConfig } from 'cf/config';

// Assets-only Worker: Astro builds a fully static site, Cloudflare serves it from the edge.
export default defineConfig({
  worker: {
    name: 'tripsplit-web',
    compatibilityDate: '2026-10-30',
    assets: { htmlHandling: 'drop-trailing-slash', notFoundHandling: '404-page' },
    domains: ['tripspl.it', 'www.tripspl.it'],
    // Kept for smoke-testing a deploy before DNS; pages declare tripspl.it as canonical.
    workersDev: true,
    previewUrls: false,
    observability: { enabled: true, logs: { enabled: true, invocationLogs: false } },
  },
});
