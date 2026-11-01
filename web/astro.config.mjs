import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://tripspl.it',
  output: 'static',
  trailingSlash: 'never',
  build: { format: 'file', inlineStylesheets: 'always' },
  devToolbar: { enabled: false },
});
