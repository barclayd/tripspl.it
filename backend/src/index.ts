import { z } from 'zod';
import type { TripSnapshot } from '../../contracts/tripsplit-v1';
import { authenticate, appleSignIn, challenge, deleteAccount, logout, processDeletions, rateLimit, refresh, registerTarget } from './auth';
import { AppError, assert, errorResponse, readJSON } from './errors';
import { getFX } from './fx';
import { id, parse, snapshotSchema, syncSchema } from './validation';
export { TripRoom } from './trip-room';

function json(value: unknown, status = 200): Response { return Response.json(value, { status, headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } }); }
async function route(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const url = new URL(request.url), path = url.pathname, method = request.method;
  if (path === '/v1/health' && method === 'GET') return json({ ok: true });
  if (env.MAINTENANCE_MODE === '1') throw new AppError(503, 'MAINTENANCE', 'TripSplit is temporarily unavailable for maintenance.', true);
  if (path === '/.well-known/apple-app-site-association' && method === 'GET') {
    assert(/^[A-Z0-9]{10}\.[A-Za-z0-9.-]+$/.test(env.APPLE_APP_ID), 'LINKS_NOT_CONFIGURED', 'Universal links are not configured.', 404);
    return json({ applinks: { details: [{ appIDs: [env.APPLE_APP_ID], components: [{ '/': '/invite/*' }] }] } });
  }
  if (/^\/invite\/[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+$/.test(path) && method === 'GET') {
    return new Response('<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1"><title>TripSplit invitation</title><h1>TripSplit invitation</h1><p>Open this invitation on an iPhone with TripSplit installed. Sign in with Apple to join the trip.</p></html>', { headers: { 'Content-Type': 'text/html;charset=utf-8', 'Cache-Control': 'no-store', 'Content-Security-Policy': "default-src 'none'; style-src 'none'; frame-ancestors 'none'", 'Referrer-Policy': 'no-referrer' } });
  }
  assert(path.startsWith('/v1/'), 'NOT_FOUND', 'Endpoint not found.', 404);
  if (path.startsWith('/v1/auth/') && method === 'POST') {
    await rateLimit(env, `auth:${request.headers.get('CF-Connecting-IP') ?? 'local'}`, 30);
    if (path === '/v1/auth/apple/challenge') { parse(z.strictObject({}), await readJSON(request, 1024)); return json(await challenge(env)); }
    if (path === '/v1/auth/apple') return json(await appleSignIn(env, await readJSON(request, 32768)));
    if (path === '/v1/auth/refresh') return json(await refresh(env, await readJSON(request, 1024)));
  }
  if (path === '/v1/fx' && method === 'GET') {
    await rateLimit(env, `fx:${request.headers.get('CF-Connecting-IP') ?? 'local'}`, 30);
    return json(await getFX(env, url.searchParams.get('from') ?? '', url.searchParams.get('to') ?? '', url.searchParams.get('date') ?? ''));
  }
  const user = await authenticate(request, env);
  await rateLimit(env, `user:${user.id}`, 240);
  if (path === '/v1/auth/logout' && method === 'POST') { await logout(env, user, await readJSON(request, 1024)); return json({ ok: true }); }
  if (path === '/v1/me' && method === 'GET') return json({ id: user.id, displayName: user.displayName });
  if (path === '/v1/me' && method === 'DELETE') {
    parse(z.strictObject({}), await readJSON(request, 1024));
    await deleteAccount(env, user.id); ctx.waitUntil(processDeletions(env));
    return json({ status: 'pending' }, 202);
  }
  if (path === '/v1/trips' && method === 'GET') {
    const cursor = url.searchParams.get('cursor'); if (cursor !== null) parse(id, cursor);
    // Targets include acknowledged creates/joins even while the discovery outbox is retrying.
    const candidates = await env.DB.prepare('SELECT trip_id FROM user_trip_targets WHERE user_id=? AND trip_id>? ORDER BY trip_id LIMIT 2').bind(user.id, cursor ?? '').all<{ trip_id: string }>();
    const page = candidates.results.slice(0, 1), trips: TripSnapshot[] = [];
    for (const candidate of page) {
      const result = await env.TRIPS.getByName(candidate.trip_id).execute(user, { type: 'read' });
      if (result.ok) trips.push(result.value as TripSnapshot);
      else if (result.error.status !== 403 && result.error.status !== 404) throw new AppError(result.error.status, result.error.code, result.error.message, result.error.retryable);
    }
    return json({ trips, nextCursor: candidates.results.length > 1 ? page.at(-1)!.trip_id : null });
  }
  if (path === '/v1/trips' && method === 'POST') {
    const input = parse(z.strictObject({ operationId: id, trip: snapshotSchema }), await readJSON(request));
    await registerTarget(env, user.id, input.trip.id);
    const result = await env.TRIPS.getByName(input.trip.id).execute(user, { type: 'create', operationId: input.operationId, trip: input.trip });
    if (!result.ok) throw new AppError(result.error.status, result.error.code, result.error.message, result.error.retryable);
    return json(result.value, 201);
  }
  const match = /^\/v1\/trips\/([A-Za-z0-9_-]{1,128})(?:\/(.*))?$/.exec(path);
  if (match) {
    const tripId = match[1]!, suffix = match[2] ?? '', room = env.TRIPS.getByName(tripId);
    if (suffix === 'live' && method === 'GET') {
      assert(request.headers.get('Upgrade')?.toLowerCase() === 'websocket', 'UPGRADE_REQUIRED', 'Use a WebSocket upgrade.', 426);
      return room.fetch(request);
    }
    const action = await (async () => {
      if (!suffix && method === 'GET') return { type: 'read' } as const;
      if (suffix === 'sync' && method === 'POST') return { type: 'sync', request: parse(syncSchema, await readJSON(request)) } as const;
      if (suffix === 'invites' && method === 'POST') return { type: 'invite', ...parse(z.strictObject({ travellerId: id }), await readJSON(request, 1024)) } as const;
      const invite = /^invites\/([A-Za-z0-9_-]{1,128})(\/accept)?$/.exec(suffix);
      if (invite && invite[2] && method === 'POST') {
        const body = parse(z.strictObject({ token: z.string().regex(/^[a-f0-9]{64}$/) }), await readJSON(request, 1024));
        return { type: 'accept', inviteId: invite[1]!, token: body.token } as const;
      }
      if (invite && !invite[2] && method === 'DELETE') return { type: 'revokeInvite', inviteId: invite[1]! } as const;
      const member = /^members\/([A-Za-z0-9_-]{1,128})$/.exec(suffix);
      if (member && method === 'DELETE') return { type: 'removeMember', travellerId: member[1]! } as const;
      throw new AppError(404, 'NOT_FOUND', 'Endpoint not found.');
    })();
    const result = await room.execute(user, action);
    if (!result.ok) throw new AppError(result.error.status, result.error.code, result.error.message, result.error.retryable);
    return json(result.value);
  }
  throw new AppError(404, 'NOT_FOUND', 'Endpoint not found.');
}
export default {
  async fetch(request, env, ctx): Promise<Response> {
    try { return await route(request, env, ctx); } catch (error) { return errorResponse(error); }
  },
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
