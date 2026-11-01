import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// Keep the existing Wrangler login; pass its credential only in child-process memory.
const account = '3343118697a4beccae42090c4520cd29';
if (process.env.CLOUDFLARE_ACCOUNT_ID && process.env.CLOUDFLARE_ACCOUNT_ID !== account) {
  throw new Error('This deployment targets the configured TripSplit Cloudflare account.');
}
const env = { ...process.env, CLOUDFLARE_ACCOUNT_ID: account };
if (!env.CLOUDFLARE_API_TOKEN) {
  const auth = spawnSync('bunx', ['wrangler', 'auth', 'token', '--json'], {
    encoding: 'utf8', timeout: 60_000, stdio: ['ignore', 'pipe', 'pipe'],
  });
  if (auth.status !== 0) {
    throw new Error('Wrangler authentication is unavailable. Run bunx wrangler whoami or provide CLOUDFLARE_API_TOKEN.');
  }
  try {
    const credential = JSON.parse(auth.stdout);
    if (typeof credential.token !== 'string' || !credential.token) throw new Error();
    env.CLOUDFLARE_API_TOKEN = credential.token;
  } catch {
    throw new Error('Wrangler did not return a usable authentication token.');
  }
}
const binary = fileURLToPath(new URL('../node_modules/.bin/cf', import.meta.url));
const result = spawnSync(binary, process.argv.slice(2), { env, stdio: 'inherit' });
if (result.error) throw new Error('The project Cloudflare CLI could not start. Run bun install --frozen-lockfile first.');
process.exitCode = result.status ?? 1;
