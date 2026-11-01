import { env } from 'cloudflare:workers';
import { beforeAll, describe, expect, it, vi } from 'vitest';
import { exportJWK, exportPKCS8, generateKeyPair, SignJWT } from 'jose';
import type { Session } from '../../contracts/tripsplit-v1';
import { appleSignIn, authenticate, challenge, deleteAccount, processDeletions, refresh } from '../src/auth';
import { encrypt, sha256 } from '../src/crypto';
import { create, request, session } from './fixtures';

let appleKeys: Awaited<ReturnType<typeof generateKeyPair>>;
let privateKey: string;
beforeAll(async () => {
  appleKeys = await generateKeyPair('RS256', { extractable: true });
  const clientKeys = await generateKeyPair('ES256', { extractable: true });
  privateKey = await exportPKCS8(clientKeys.privateKey);
});
function configured(): Env { return { ...env, APPLE_AUDIENCE: 'it.tripspl.TripSplit', APPLE_TEAM_ID: 'TESTTEAM00', APPLE_KEY_ID: 'test-key', APPLE_PRIVATE_KEY: privateKey }; }
async function appleToken(nonce: string, subject = 'apple-user', audience = 'it.tripspl.TripSplit'): Promise<string> {
  return new SignJWT({ nonce }).setProtectedHeader({ alg: 'RS256', kid: 'apple-test' }).setIssuer('https://appleid.apple.com').setSubject(subject).setAudience(audience).setIssuedAt().setExpirationTime('5m').sign(appleKeys.privateKey);
}
async function mockApple(token: string, rejectRevocation = false): Promise<ReturnType<typeof vi.spyOn>> {
  const jwk = await exportJWK(appleKeys.publicKey);
  return vi.spyOn(globalThis, 'fetch').mockImplementation(async (input) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    if (url.endsWith('/auth/keys')) return Response.json({ keys: [{ ...jwk, kid: 'apple-test', alg: 'RS256', use: 'sig' }] });
    if (url.endsWith('/auth/token')) return Response.json({ id_token: token, refresh_token: 'apple-refresh-grant' });
    if (url.endsWith('/auth/revoke')) return rejectRevocation ? Response.json({ error: 'temporarily_unavailable' }, { status: 503 }) : Response.json({});
    throw new Error('Unexpected network request');
  });
}
async function prepareRefresh(user: Session): Promise<Env> {
  const config = configured();
  await env.DB.prepare('INSERT INTO apple_identities(subject,user_id,encrypted_grant) VALUES(?,?,?)').bind(user.user.id, user.user.id, await encrypt('refresh-grant', config.SESSION_ENCRYPTION_KEY, user.user.id)).run();
  await mockApple(await appleToken('not-used-on-refresh', user.user.id));
  return config;
}
describe('authentication and account lifecycle', () => {
  it('fails closed without Apple configuration and exposes no development authentication endpoint', async () => {
    expect((await request('/auth/apple/challenge', undefined, {})).status).toBe(503);
    expect((await request('/auth/dev', undefined, {})).status).toBe(401);
  });
  it('verifies Apple signatures/audience/nonce and exchanges code before issuing hashed sessions', async () => {
    const config = configured(), authChallenge = await challenge(config), nonce = await sha256(authChallenge.nonce), token = await appleToken(nonce);
    await mockApple(token);
    await expect(appleSignIn(config, { challengeId: authChallenge.id, identityToken: await appleToken(nonce, 'apple-user', 'wrong.audience'), authorizationCode: 'code' })).rejects.toMatchObject({ code: 'APPLE_TOKEN' });
    await expect(appleSignIn(config, { challengeId: authChallenge.id, identityToken: await appleToken('wrong-nonce'), authorizationCode: 'code' })).rejects.toMatchObject({ code: 'APPLE_NONCE' });
    const signedIn = await appleSignIn(config, { challengeId: authChallenge.id, identityToken: token, authorizationCode: 'code', displayName: 'Alice' });
    expect(signedIn.user.displayName).toBe('Alice');
    const stored = await env.DB.prepare('SELECT access_hash,refresh_hash FROM sessions WHERE user_id=?').bind(signedIn.user.id).first<{ access_hash: string; refresh_hash: string }>();
    expect(stored).toEqual({ access_hash: await sha256(signedIn.accessToken), refresh_hash: await sha256(signedIn.refreshToken) });
    const identity = await env.DB.prepare('SELECT encrypted_grant FROM apple_identities WHERE user_id=?').bind(signedIn.user.id).first<{ encrypted_grant: string }>();
    expect(identity?.encrypted_grant).not.toContain('apple-refresh-grant');
    await expect(appleSignIn(config, { challengeId: authChallenge.id, identityToken: token, authorizationCode: 'code' })).rejects.toMatchObject({ code: 'AUTH_CHALLENGE' });
  });
  it('rejects an exchanged code from a different Apple account', async () => {
    const config = configured(), authChallenge = await challenge(config), nonce = await sha256(authChallenge.nonce);
    await mockApple(await appleToken(nonce, 'other-account'));
    await expect(appleSignIn(config, { challengeId: authChallenge.id, identityToken: await appleToken(nonce), authorizationCode: 'other-code' })).rejects.toMatchObject({ code: 'APPLE_EXCHANGE' });
    expect(await env.DB.prepare('SELECT count(*) AS n FROM sessions').first()).toEqual({ n: 0 });
  });
  it('rotates refresh/access credentials once, rejects concurrent refresh and logs out', async () => {
    const original = await session(), config = await prepareRefresh(original);
    const attempts = await Promise.allSettled([refresh(config, { refreshToken: original.refreshToken }), refresh(config, { refreshToken: original.refreshToken })]);
    expect(attempts.filter(result => result.status === 'fulfilled')).toHaveLength(1);
    const result = attempts.find(result => result.status === 'fulfilled')!;
    if (result.status !== 'fulfilled') throw new Error('No session');
    const rotated = result.value;
    expect((await request('/me', original)).status).toBe(401); expect((await request('/me', rotated)).status).toBe(200);
    expect((await request('/auth/logout', rotated, { refreshToken: rotated.refreshToken })).status).toBe(200);
    expect((await request('/me', rotated)).status).toBe(401);
  });
  it('persists deletion before revoking sessions, transfers shared ownership and anonymizes traveller', async () => {
    const owner = await session(), member = await session(), trip = await create(owner);
    const invite = await (await request(`/trips/${trip.id}/invites`, owner, { travellerId: 'b' })).json<{ id: string; token: string }>();
    await request(`/trips/${trip.id}/invites/${invite.id}/accept`, member, { token: invite.token });
    await deleteAccount(env, owner.user.id);
    expect(await env.DB.prepare('SELECT user_id FROM deletion_jobs').first()).toEqual({ user_id: owner.user.id });
    expect((await request('/me', owner)).status).toBe(401);
    await processDeletions(env);
    const remaining = await (await request(`/trips/${trip.id}`, member)).json<{ role: string; ownerTravellerId: string; travellers: { id: string; name: string; archived: boolean }[] }>();
    expect(remaining.role).toBe('owner'); expect(remaining.ownerTravellerId).toBe('b');
    expect(remaining.travellers.find(t => t.id === 'a')).toMatchObject({ name: 'Deleted traveller', archived: true });
    expect(await env.DB.prepare('SELECT count(*) AS n FROM users WHERE id=?').bind(owner.user.id).first()).toEqual({ n: 0 });
  });
  it('retries Apple revocation after outages and keeps account disabled until cleanup finishes', async () => {
    const config = configured(), user = await session(), trip = await create(user);
    const grant = await encrypt('revocation-grant', config.SESSION_ENCRYPTION_KEY, user.user.id);
    await env.DB.prepare('INSERT INTO apple_identities(subject,user_id,encrypted_grant) VALUES(?,?,?)').bind('deleting-apple-user', user.user.id, grant).run();
    const mock = await mockApple('', true);
    await deleteAccount(config, user.user.id); await processDeletions(config);
    expect(await env.DB.prepare('SELECT attempts FROM deletion_jobs').first()).toEqual({ attempts: 1 });
    expect((await request('/me', user)).status).toBe(401);
    expect(await env.DB.prepare('SELECT deleting FROM users WHERE id=?').bind(user.user.id).first()).toEqual({ deleting: 1 });
    mock.mockRestore(); await mockApple('');
    await env.DB.prepare('UPDATE deletion_jobs SET next_attempt_at=0').run(); await processDeletions(config);
    expect(await env.DB.prepare('SELECT count(*) AS n FROM deletion_jobs').first()).toEqual({ n: 0 });
    const stranger = await session(); expect((await request(`/trips/${trip.id}`, stranger)).status).toBe(403);
  });
  it('expires access tokens independently of refresh lifetime', async () => {
    const user = await session(), config = await prepareRefresh(user);
    await env.DB.prepare('UPDATE sessions SET access_expires_at=0 WHERE user_id=?').bind(user.user.id).run();
    await expect(authenticate(new Request('https://api.example.com', { headers: { authorization: `Bearer ${user.accessToken}` } }), env)).rejects.toMatchObject({ status: 401 });
    const rotated: Session = await refresh(config, { refreshToken: user.refreshToken }); expect((await request('/me', rotated)).status).toBe(200);
  });
  it('revokes local sessions when Apple revokes the stored grant, but retains them through provider outages', async () => {
    const user = await session(), config = await prepareRefresh(user);
    for (const status of [429, 503]) {
      vi.restoreAllMocks();
      vi.spyOn(globalThis, 'fetch').mockImplementation(async () => Response.json({ error: 'temporarily_unavailable' }, { status }));
      await expect(refresh(config, { refreshToken: user.refreshToken })).rejects.toMatchObject({ retryable: true });
      expect((await request('/me', user)).status).toBe(200);
    }
    vi.restoreAllMocks();
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => Response.json({ error: 'invalid_grant' }, { status: 400 }));
    await expect(refresh(config, { refreshToken: user.refreshToken })).rejects.toMatchObject({ code: 'APPLE_REVOKED' });
    expect((await request('/me', user)).status).toBe(401);
  });

});
