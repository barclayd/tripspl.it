import { fileURLToPath } from 'node:url';
import { cleanBuildOutputDir, writeAssets, writeRootConfig, writeWorkerConfig } from '@cloudflare/build-output-utils';
import { loadAndParseConfig } from '@cloudflare/config';

// cf expects Astro's Cloudflare adapter to write Build Output. The site is fully static, so turn
// dist/ into an assets-only Worker instead of shipping a server adapter that would never run.
const root = fileURLToPath(new URL('..', import.meta.url));
const context = { isPreview: false, mode: 'production' };
const { result } = await loadAndParseConfig(`${root}cloudflare.config.ts`, context);
if (!result.success) throw result.error;

await cleanBuildOutputDir(root);
await writeAssets({ root, sourceDirectory: `${root}dist` });
await writeWorkerConfig({ root, config: result.data.worker });
await writeRootConfig(root, result.data.settings, context);
console.log('Wrote .cloudflare/output from dist/');
