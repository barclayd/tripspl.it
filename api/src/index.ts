import app from './app';
import { processDeletions } from './services/auth';

export { TripRoom } from './durable-objects/trip-room';

export default {
  fetch: app.fetch,
  async scheduled(_controller, env, ctx): Promise<void> {
    if (env.MAINTENANCE_MODE === '1') return;
    ctx.waitUntil((async () => {
      await processDeletions(env);
      await env.DB.batch([
        env.DB.prepare('DELETE FROM auth_challenges WHERE expires_at<?').bind(Date.now()),
        env.DB.prepare('DELETE FROM sessions WHERE refresh_expires_at<?').bind(Date.now()),
        env.DB.prepare('DELETE FROM rate_limits WHERE expires_at<?').bind(Date.now()),
      ]);
    })());
  },
} satisfies ExportedHandler<Env>;
