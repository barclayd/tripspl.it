import { OpenAPIHono } from '@hono/zod-openapi';
import { authenticateUser, authRateLimit } from '../../middleware/auth';
import { appleSignIn, challenge, deleteAccount, logout, processDeletions, refresh } from '../../services/auth';
import { getFX, getFXTable } from '../../services/fx';
import { createTrip, executeRoom, listTrips } from '../../services/trips';
import type { HonoEnvironment } from '../../types/hono';
import { assert } from '../../utils/errors';
import { jsonHeaders, notFound } from '../../utils/http';
import { routes } from './routes';

export function createV1Routes() {
  const app = new OpenAPIHono<HonoEnvironment>();

  app.use('*', async (c, next) => {
    if (!c.req.path.startsWith('/v1/')) notFound();
    // Hono routes HEAD through GET. v1 only exposes explicit methods, and
    // unknown v1 endpoints authenticate before returning NOT_FOUND.
    if (c.req.method === 'HEAD') return authenticateUser(c, async () => notFound());
    await next();
  });
  app.openapi(routes.health, c => c.json({ ok: true }, 200, jsonHeaders));
  app.use('*', authRateLimit);
  app.openapi(routes.auth.challenge, async c => c.json(await challenge(c.env), 200, jsonHeaders));
  app.openapi(routes.auth.apple, async c => c.json(await appleSignIn(c.env, c.req.valid('json')), 200, jsonHeaders));
  app.openapi(routes.auth.refresh, async c => c.json(await refresh(c.env, c.req.valid('json')), 200, jsonHeaders));
  app.openapi(routes.fx, async c => {
    const { from, to, date } = c.req.valid('query');
    return c.json(await getFX(c.env, from, to, date), 200, jsonHeaders);
  });
  app.openapi(routes.fxRates, async c => {
    const { base, date } = c.req.valid('query');
    return c.json(await getFXTable(base, date), 200, jsonHeaders);
  });

  app.use('*', authenticateUser);
  app.openapi(routes.auth.logout, async c => {
    await logout(c.env, c.get('principal'), c.req.valid('json'));
    return c.json({ ok: true }, 200, jsonHeaders);
  });
  app.openapi(routes.me.get, c => {
    const user = c.get('principal');
    return c.json({ id: user.id, displayName: user.displayName }, 200, jsonHeaders);
  });
  app.openapi(routes.me.delete, async c => {
    await deleteAccount(c.env, c.get('principal').id);
    c.executionCtx.waitUntil(processDeletions(c.env));
    return c.json({ status: 'pending' }, 202, jsonHeaders);
  });
  app.openapi(routes.trips.list, async c => c.json(await listTrips(c.env, c.get('principal'), c.req.valid('query').cursor), 200, jsonHeaders));
  app.openapi(routes.trips.create, async c => c.json(await createTrip(c.env, c.get('principal'), c.req.valid('json')), 201, jsonHeaders));

  app.use('/trips/*', async (c, next) => {
    // Validate the raw path before Hono decodes parameters. Encoded aliases,
    // overlong IDs and unknown suffixes retain the original 404 contract.
    if (!/^\/v1\/trips\/[A-Za-z0-9_-]{1,128}(?:\/(?:sync|live|invites(?:\/[A-Za-z0-9_-]{1,128}(?:\/accept)?)?|members\/[A-Za-z0-9_-]{1,128})?)?$/.test(c.req.path)) notFound();
    await next();
  });
  app.openapi(routes.trips.get, async c => c.json(await executeRoom(c.env, c.get('principal'), c.req.valid('param').tripId, { type: 'read' }), 200, jsonHeaders));
  // The previous router accepted a trailing slash only on the trip root.
  app.openapi({ ...routes.trips.get, path: '/trips/{tripId}/', hide: true }, async c => c.json(await executeRoom(c.env, c.get('principal'), c.req.valid('param').tripId, { type: 'read' }), 200, jsonHeaders));
  app.openapi(routes.trips.sync, async c => c.json(await executeRoom(c.env, c.get('principal'), c.req.valid('param').tripId, { type: 'sync', request: c.req.valid('json') }), 200, jsonHeaders));
  app.openapi(routes.trips.live, c => {
    assert(c.req.header('Upgrade')?.toLowerCase() === 'websocket', 'UPGRADE_REQUIRED', 'Use a WebSocket upgrade.', 426);
    return c.env.TRIPS.getByName(c.req.valid('param').tripId).fetch(c.req.raw);
  });
  app.openapi(routes.trips.invite, async c => c.json(await executeRoom(c.env, c.get('principal'), c.req.valid('param').tripId, { type: 'invite', ...c.req.valid('json') }), 200, jsonHeaders));
  app.openapi(routes.trips.accept, async c => {
    const { tripId, inviteId } = c.req.valid('param');
    return c.json(await executeRoom(c.env, c.get('principal'), tripId, { type: 'accept', inviteId, token: c.req.valid('json').token }), 200, jsonHeaders);
  });
  app.openapi(routes.trips.revokeInvite, async c => {
    const { tripId, inviteId } = c.req.valid('param');
    return c.json(await executeRoom(c.env, c.get('principal'), tripId, { type: 'revokeInvite', inviteId }), 200, jsonHeaders);
  });
  app.openapi(routes.trips.delete, async c => c.json(await executeRoom(c.env, c.get('principal'), c.req.valid('param').tripId, { type: 'delete' }), 200, jsonHeaders));
  app.openapi(routes.trips.removeMember, async c => {
    const { tripId, travellerId } = c.req.valid('param');
    return c.json(await executeRoom(c.env, c.get('principal'), tripId, { type: 'removeMember', travellerId }), 200, jsonHeaders);
  });
  return app;
}
