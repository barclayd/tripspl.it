import { beforeEach, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:workers';
import { applyD1Migrations, reset } from 'cloudflare:test';

declare global { namespace Cloudflare { interface Env { TEST_MIGRATIONS: import('cloudflare:test').D1Migration[] } } }
declare module 'cloudflare:workers' { interface ProvidedEnv extends Env {} }

beforeEach(async () => { await reset(); await applyD1Migrations(env.DB, env.TEST_MIGRATIONS); });
afterEach(async () => { vi.restoreAllMocks(); await reset(); });
