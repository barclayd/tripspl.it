import { env, exports } from 'cloudflare:workers';
import { createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import type { APIError, TripSnapshot } from '../../contracts/tripsplit-v1';
import worker from '../src/index';
import { sha256 } from '../src/utils/crypto';
import { create, request, session } from './fixtures';

async function expectError(response: Response, status: number, code: string, message?: string, retryable = false) {
  expect(response.status).toBe(status);
  expect(response.headers.get('Content-Type')).toBe('application/json');
  expect(response.headers.get('Cache-Control')).toBe('no-store');
  const body = await response.json<APIError>();
  expect(Object.keys(body)).toEqual(['error']);
  expect(Object.keys(body.error).sort()).toEqual(['code', 'message', 'retryable']);
  expect(body.error).toMatchObject({ code, retryable, ...(message === undefined ? {} : { message }) });
}

function raw(path: string, body: BodyInit | null, contentType = 'application/json', headers: Record<string, string> = {}) {
  return exports.default.fetch(`https://api.example.com${path}`, { method: 'POST', headers: { 'Content-Type': contentType, ...headers }, body });
}

describe('HTTP middleware compatibility', () => {
  it('keeps strict content types, missing/malformed bodies, fatal UTF-8 and validation error envelopes', async () => {
    for (const mediaType of ['text/plain', 'application/problem+json', 'APPLICATION/JSON']) {
      await expectError(await raw('/v1/auth/refresh', '{}', mediaType), 415, 'CONTENT_TYPE', 'Use application/json.');
    }
    await expectError(await raw('/v1/auth/refresh', null), 400, 'INVALID_JSON', 'A JSON body is required.');
    await expectError(await raw('/v1/auth/refresh', '{'), 400, 'INVALID_JSON', 'Request body must be valid JSON.');
    await expectError(await raw('/v1/auth/refresh', new Uint8Array([123, 34, 120, 34, 58, 34, 0xc3, 0x28, 34, 125])), 400, 'INVALID_JSON', 'Request body must be valid JSON.');
    await expectError(await raw('/v1/auth/refresh', '{"refreshToken":"bad"}'), 400, 'VALIDATION', 'Invalid request fields: refreshToken');
    // The original media-type check accepts parameters without interpreting them.
    await expectError(await raw('/v1/auth/refresh', '{"refreshToken":"bad"}', 'application/json;legacy-flag'), 400, 'VALIDATION', 'Invalid request fields: refreshToken');
    await expectError(await raw('/v1/auth/apple/challenge', '{"extra":true}'), 400, 'VALIDATION', 'Invalid request fields: ');
  });

  it('preserves Apple configuration and authentication checks in their original order', async () => {
    // Test bindings intentionally omit Apple secrets. JSON is read first;
    // sign-in checks configuration before fields, refresh validates fields first.
    await expectError(await raw('/v1/auth/apple', '{'), 400, 'INVALID_JSON');
    await expectError(await raw('/v1/auth/apple', '{}'), 503, 'AUTH_NOT_CONFIGURED');
    await expectError(await raw('/v1/auth/refresh', '{}'), 400, 'VALIDATION');
    await expectError(await raw('/v1/trips', '{'), 401, 'UNAUTHENTICATED');
    const owner = await session();
    await expectError(await raw('/v1/trips', '{', 'application/json', { authorization: `Bearer ${owner.accessToken}` }), 400, 'INVALID_JSON');
  });

  it('enforces each endpoint byte limit including exact boundary bodies', async () => {
    const owner = await session();
    const cases = [
      { path: '/v1/auth/apple/challenge', maximum: 1024, status: 503, code: 'AUTH_NOT_CONFIGURED', headers: {} },
      { path: '/v1/auth/apple', maximum: 32768, status: 503, code: 'AUTH_NOT_CONFIGURED', headers: {} },
      { path: '/v1/trips', maximum: 1_048_576, status: 400, code: 'VALIDATION', headers: { authorization: `Bearer ${owner.accessToken}` } },
    ];
    for (const { path, maximum, status, code, headers } of cases) {
      await expectError(await raw(path, '{}' + ' '.repeat(maximum - 2), 'application/json', headers), status, code);
      await expectError(await raw(path, '{}' + ' '.repeat(maximum - 1), 'application/json', headers), 413, 'BODY_TOO_LARGE', 'Request body exceeds the limit.');
    }
  });

  it('bounds an untrusted chunked stream before applying any operations', async () => {
    const owner = await session(), trip = await create(owner);
    let cancelled = false;
    const body = new ReadableStream<Uint8Array>({
      pull(controller) { controller.enqueue(new Uint8Array(65536).fill(32)); },
      cancel() { cancelled = true; },
    });
    const response = await worker.fetch(new Request(`https://api.example.com/v1/trips/${trip.id}/sync`, {
      method: 'POST', headers: { authorization: `Bearer ${owner.accessToken}`, 'Content-Type': 'application/json', 'Content-Length': '1' }, body,
    }), env, createExecutionContext());
    await expectError(response, 413, 'BODY_TOO_LARGE');
    expect(cancelled).toBe(true);
    const unchanged = await (await request(`/trips/${trip.id}`, owner)).json<TripSnapshot>();
    expect(unchanged.revision).toBe(trip.revision);
    expect(unchanged.expenses).toEqual([]);
  });

  it('keeps unknown paths protected and rejects implicit HEAD, encoded aliases and extra slashes', async () => {
    const owner = await session(), trip = await create(owner);
    await expectError(await exports.default.fetch('https://api.example.com/unknown'), 404, 'NOT_FOUND');
    await expectError(await exports.default.fetch('https://api.example.com/v1'), 404, 'NOT_FOUND');
    await expectError(await request('/unknown'), 401, 'UNAUTHENTICATED');
    await expectError(await request('/unknown', owner), 404, 'NOT_FOUND');
    await expectError(await request('/health', undefined, undefined, 'POST'), 401, 'UNAUTHENTICATED');
    expect((await request('/health', undefined, undefined, 'HEAD')).status).toBe(401);
    expect((await request('/health', owner, undefined, 'HEAD')).status).toBe(404);
    for (const path of ['/health/', '/%68ealth', `/trips/%${trip.id.charCodeAt(0).toString(16)}${trip.id.slice(1)}`, `/trips/${trip.id}/sync/`, `/trips/${'x'.repeat(129)}`]) {
      await expectError(await request(path, owner), 404, 'NOT_FOUND');
    }
    expect((await request(`/trips/${trip.id}/`, owner)).status).toBe(200);
  });

  it('retains first query values and the public FX validation contract', async () => {
    const response = await request('/fx?from=GBP&from=ZZZ&to=GBP&to=ZZZ&date=2026-10-01&date=invalid');
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ from: 'GBP', to: 'GBP', rate: '1' });
    await expectError(await request('/fx?from=GBP&to=GBP&date=invalid'), 400, 'VALIDATION', 'Invalid request fields: , ');
    const owner = await session();
    await expectError(await request('/trips?cursor=', owner), 400, 'VALIDATION', 'Invalid request fields: , ');
    const first = await create(owner), second = await create(owner);
    const cursor = [first.id, second.id].sort()[0]!;
    const page = await (await request(`/trips?cursor=${cursor}&cursor=invalid!`, owner)).json<{ trips: TripSnapshot[] }>();
    expect(page.trips).toHaveLength(1);
  });

  it('applies both auth-IP and authenticated-account limits to logout', async () => {
    const owner = await session(), ip = '192.0.2.10';
    await expectError(await raw('/v1/auth/logout', '{}', 'application/json', { authorization: `Bearer ${owner.accessToken}`, 'CF-Connecting-IP': ip }), 400, 'VALIDATION');
    const bucket = Math.floor(Date.now() / 60_000);
    for (const key of [`auth:${ip}`, `user:${owner.user.id}`]) {
      expect(await env.DB.prepare('SELECT count FROM rate_limits WHERE key=?').bind(await sha256(`${key}:${bucket}`)).first()).toEqual({ count: 1 });
    }
  });

  it('preserves JSON and invitation security headers and passes WebSocket errors through', async () => {
    const health = await request('/health');
    expect(health.headers.get('Content-Type')).toBe('application/json');
    expect(health.headers.get('Cache-Control')).toBe('no-store');
    expect(health.headers.get('X-Content-Type-Options')).toBe('nosniff');
    const invitation = await exports.default.fetch('https://api.example.com/invite/trip/invite');
    expect(invitation.status).toBe(200);
    expect(invitation.headers.get('Content-Security-Policy')).toBe("default-src 'none'; style-src 'none'; frame-ancestors 'none'");
    expect(invitation.headers.get('Referrer-Policy')).toBe('no-referrer');
    expect(invitation.headers.get('Cache-Control')).toBe('no-store');
    const owner = await session(), trip = await create(owner);
    await expectError(await request(`/trips/${trip.id}/live`, owner), 426, 'UPGRADE_REQUIRED', 'Use a WebSocket upgrade.');
  });

  it('allows only GET health during maintenance, including public links', async () => {
    const maintenanceEnv = { ...env, MAINTENANCE_MODE: '1' };
    for (const path of ['/v1/me', '/.well-known/apple-app-site-association', '/invite/trip/invite', '/unknown']) {
      await expectError(await worker.fetch(new Request(`https://api.example.com${path}`), maintenanceEnv, createExecutionContext()), 503, 'MAINTENANCE', 'TripSplit is temporarily unavailable for maintenance.', true);
    }
    expect((await worker.fetch(new Request('https://api.example.com/v1/health', { method: 'HEAD' }), maintenanceEnv, createExecutionContext())).status).toBe(503);
    expect((await worker.fetch(new Request('https://api.example.com/v1/health'), maintenanceEnv, createExecutionContext())).status).toBe(200);
  });

  it('retains scheduled cleanup and its maintenance pause', async () => {
    await env.DB.prepare('INSERT INTO auth_challenges(id,nonce_hash,expires_at) VALUES(?,?,?)').bind('expired', 'unused', 0).run();
    await env.DB.prepare('INSERT INTO rate_limits(key,count,expires_at) VALUES(?,?,?)').bind('expired', 1, 0).run();
    const controller = { scheduledTime: Date.now(), cron: '*/5 * * * *', noRetry() {} };
    const paused = createExecutionContext();
    await worker.scheduled(controller, { ...env, MAINTENANCE_MODE: '1' }, paused);
    await waitOnExecutionContext(paused);
    expect(await env.DB.prepare('SELECT id FROM auth_challenges').first()).toEqual({ id: 'expired' });
    const running = createExecutionContext();
    await worker.scheduled(controller, env, running);
    await waitOnExecutionContext(running);
    expect(await env.DB.prepare('SELECT id FROM auth_challenges').first()).toBeNull();
    expect(await env.DB.prepare('SELECT key FROM rate_limits').first()).toBeNull();
  });
});
