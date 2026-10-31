import { createRemoteJWKSet, errors as joseErrors, importPKCS8, jwtVerify, SignJWT } from 'jose';
import { z } from 'zod';
import type { AuthChallenge, Session, User } from '../../contracts/tripsplit-v1';
import { AppError, assert } from './errors';
import { decrypt, encrypt, randomToken, sha256 } from './crypto';
import { id, parse } from './validation';
import { limitedText } from './fx';

const APPLE_ISSUER = 'https://appleid.apple.com';
const ACCESS_TTL = 15 * 60_000, REFRESH_TTL = 30 * 86_400_000;
const appleKeys = createRemoteJWKSet(new URL(`${APPLE_ISSUER}/auth/keys`), { timeoutDuration: 8000 });
async function verifyAppleToken(env: Env, token: string, fresh = false) {
  try {
    return await jwtVerify(token, appleKeys, { issuer: APPLE_ISSUER, audience: env.APPLE_AUDIENCE, algorithms: ['RS256'], requiredClaims: ['iss', 'aud', 'sub', 'iat', 'exp'], clockTolerance: 5, ...(fresh ? { maxTokenAge: '10m' } : {}) });
  } catch (error) {
    if (error instanceof joseErrors.JWTExpired || error instanceof joseErrors.JWTClaimValidationFailed || error instanceof joseErrors.JWSInvalid || error instanceof joseErrors.JWSSignatureVerificationFailed || error instanceof joseErrors.JWTInvalid || error instanceof joseErrors.JOSEAlgNotAllowed || error instanceof joseErrors.JWKSNoMatchingKey) throw new AppError(401, 'APPLE_TOKEN', 'Apple identity could not be verified.');
    throw new AppError(503, 'APPLE_UNAVAILABLE', 'Apple identity verification is temporarily unavailable.', true);
  }
}
export interface Principal extends User { sessionId: string; accessExpiresAt: number }
export function requireApple(env: Env): void {
  if (!env.APPLE_AUDIENCE || !env.APPLE_TEAM_ID || !env.APPLE_KEY_ID || !env.APPLE_PRIVATE_KEY || !env.SESSION_ENCRYPTION_KEY) throw new AppError(503, 'AUTH_NOT_CONFIGURED', 'Sign in with Apple is not configured on this server.', false);
}
export async function rateLimit(env: Env, key: string, maximum: number, windowMs = 60_000): Promise<void> {
  const bucket = Math.floor(Date.now() / windowMs);
  const digest = await sha256(`${key}:${bucket}`);
  const row = await env.DB.prepare('INSERT INTO rate_limits(key,count,expires_at) VALUES(?,1,?) ON CONFLICT(key) DO UPDATE SET count=count+1 RETURNING count').bind(digest, (bucket + 2) * windowMs).first<{ count: number }>();
  if (!row || row.count > maximum) throw new AppError(429, 'RATE_LIMIT', 'Too many requests. Please try again shortly.', true);
}
export async function challenge(env: Env): Promise<AuthChallenge> {
  requireApple(env);
  const nonce = randomToken(), challengeId = crypto.randomUUID(), expires = Date.now() + 5 * 60_000;
  await env.DB.prepare('INSERT INTO auth_challenges(id,nonce_hash,expires_at) VALUES(?,?,?)').bind(challengeId, await sha256(nonce), expires).run();
  return { id: challengeId, nonce, expiresAt: new Date(expires).toISOString() };
}
async function clientSecret(env: Env): Promise<string> {
  requireApple(env);
  const key = await importPKCS8(env.APPLE_PRIVATE_KEY.replace(/\\n/g, '\n'), 'ES256');
  return new SignJWT({}).setProtectedHeader({ alg: 'ES256', kid: env.APPLE_KEY_ID }).setIssuer(env.APPLE_TEAM_ID).setSubject(env.APPLE_AUDIENCE).setAudience(APPLE_ISSUER).setIssuedAt().setExpirationTime('5m').sign(key);
}
export async function appleSignIn(env: Env, value: unknown): Promise<Session> {
  requireApple(env);
  const input = parse(z.strictObject({ challengeId: id, identityToken: z.string().min(1).max(16384), authorizationCode: z.string().min(1).max(4096), displayName: z.string().trim().min(1).max(120).optional() }), value);
  const challengeRow = await env.DB.prepare('SELECT nonce_hash,expires_at FROM auth_challenges WHERE id=?').bind(input.challengeId).first<{ nonce_hash: string; expires_at: number }>();
  assert(challengeRow && challengeRow.expires_at > Date.now(), 'AUTH_CHALLENGE', 'Sign-in challenge has expired or has already been used.', 401);
  let subject: string;
  try {
    const { payload } = await verifyAppleToken(env, input.identityToken, true);
    assert(typeof payload.sub === 'string' && typeof payload.nonce === 'string', 'APPLE_TOKEN', 'Apple token is missing required claims.', 401);
    assert(crypto.subtle.timingSafeEqual(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(payload.nonce)), await crypto.subtle.digest('SHA-256', new TextEncoder().encode(challengeRow.nonce_hash))), 'APPLE_NONCE', 'Apple token does not match this sign-in challenge.', 401);
    subject = payload.sub;
  } catch (error) { if (error instanceof AppError) throw error; throw new AppError(401, 'APPLE_TOKEN', 'Apple identity could not be verified.'); }
  // Consume before exchanging the one-use code. A failed exchange requires a new Apple sign-in.
  const consumed = await env.DB.prepare('DELETE FROM auth_challenges WHERE id=? AND expires_at>? RETURNING id').bind(input.challengeId, Date.now()).first();
  assert(consumed, 'AUTH_CHALLENGE', 'Sign-in challenge has already been used.', 401);
  const tokenResponse = await appleRequest(env, 'token', { grant_type: 'authorization_code', code: input.authorizationCode });
  assert(typeof tokenResponse.id_token === 'string' && typeof tokenResponse.refresh_token === 'string', 'APPLE_EXCHANGE', 'Apple did not return a valid authorization grant.', 401);
  try {
    const { payload } = await verifyAppleToken(env, tokenResponse.id_token);
    assert(payload.sub === subject && payload.nonce === challengeRow.nonce_hash, 'APPLE_EXCHANGE', 'The authorization code belongs to a different sign-in.', 401);
  } catch (error) { if (error instanceof AppError) throw error; throw new AppError(401, 'APPLE_EXCHANGE', 'Apple authorization code could not be verified.'); }
  const newId = crypto.randomUUID(), displayName = input.displayName ?? 'Traveller';
  await env.DB.batch([
    env.DB.prepare('INSERT OR IGNORE INTO users(id,display_name,created_at) SELECT ?,?,? WHERE NOT EXISTS(SELECT 1 FROM apple_identities WHERE subject=?)').bind(newId, displayName, new Date().toISOString(), subject),
    env.DB.prepare('INSERT OR IGNORE INTO apple_identities(subject,user_id) SELECT ?,id FROM users WHERE id=?').bind(subject, newId),
  ]);
  const user = await env.DB.prepare('SELECT u.id,u.display_name,u.deleting FROM users u JOIN apple_identities a ON a.user_id=u.id WHERE a.subject=?').bind(subject).first<{ id: string; display_name: string; deleting: number }>();
  assert(user && !user.deleting, 'ACCOUNT_DELETING', 'Account deletion is in progress.', 403);
  const encryptedGrant = await encrypt(tokenResponse.refresh_token, env.SESSION_ENCRYPTION_KEY, user.id);
  await env.DB.prepare('UPDATE apple_identities SET encrypted_grant=? WHERE user_id=?').bind(encryptedGrant, user.id).run();
  return issueSession(env, { id: user.id, displayName: user.display_name });
}
async function appleRequest(env: Env, endpoint: 'token' | 'revoke', parameters: Record<string, string>): Promise<Record<string, unknown>> {
  let response: Response;
  try { response = await fetch(`${APPLE_ISSUER}/auth/${endpoint}`, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ client_id: env.APPLE_AUDIENCE, client_secret: await clientSecret(env), ...parameters }), signal: AbortSignal.timeout(8000) }); }
  catch { throw new AppError(503, 'APPLE_UNAVAILABLE', 'Apple sign-in is temporarily unavailable.', true); }
  const text = await limitedText(response, 32768);
  let body: Record<string, unknown> = {};
  if (text) { try { body = JSON.parse(text); } catch { throw new AppError(502, 'APPLE_RESPONSE', 'Apple returned an invalid response.', true); } }
  if (!response.ok) {
    // A grant already revoked by Apple has no remaining authority to revoke.
    if (endpoint === 'revoke' && body.error === 'invalid_grant') return {};
    const retryable = response.status === 429 || response.status >= 500;
    throw new AppError(retryable ? 503 : 401, 'APPLE_EXCHANGE', 'Apple authorization was unsuccessful.', retryable);
  }
  return body;
}
export async function issueSession(env: Env, user: User): Promise<Session> {
  const accessToken = randomToken(), refreshToken = randomToken(), expires = Date.now() + ACCESS_TTL;
  const result = await env.DB.prepare('INSERT INTO sessions(id,user_id,access_hash,refresh_hash,access_expires_at,refresh_expires_at) SELECT ?,id,?,?,?,? FROM users WHERE id=? AND deleting=0').bind(crypto.randomUUID(), await sha256(accessToken), await sha256(refreshToken), expires, Date.now() + REFRESH_TTL, user.id).run();
  assert(result.meta.changes === 1, 'ACCOUNT_DELETING', 'This account is no longer active.', 403);
  return { user, accessToken, refreshToken, expiresAt: new Date(expires).toISOString() };
}
export async function authenticate(request: Request, env: Env): Promise<Principal> {
  const header = request.headers.get('authorization');
  assert(header && /^Bearer [a-f0-9]{64}$/.test(header), 'UNAUTHENTICATED', 'Sign in to continue.', 401);
  const row = await env.DB.prepare('SELECT u.id,u.display_name,s.id AS session_id,s.access_expires_at FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.access_hash=? AND s.access_expires_at>? AND u.deleting=0').bind(await sha256(header.slice(7)), Date.now()).first<{ id: string; display_name: string; session_id: string; access_expires_at: number }>();
  assert(row, 'UNAUTHENTICATED', 'This session has expired. Sign in again.', 401);
  return { id: row.id, displayName: row.display_name, sessionId: row.session_id, accessExpiresAt: row.access_expires_at };
}
export async function refresh(env: Env, value: unknown): Promise<Session> {
  const { refreshToken: oldToken } = parse(z.strictObject({ refreshToken: z.string().regex(/^[a-f0-9]{64}$/) }), value);
  requireApple(env);
  const current = await env.DB.prepare('SELECT s.user_id,a.subject,a.encrypted_grant FROM sessions s JOIN users u ON u.id=s.user_id JOIN apple_identities a ON a.user_id=u.id WHERE s.refresh_hash=? AND s.refresh_expires_at>? AND u.deleting=0').bind(await sha256(oldToken), Date.now()).first<{ user_id: string; subject: string; encrypted_grant: string | null }>();
  assert(current?.encrypted_grant, 'UNAUTHENTICATED', 'Refresh token has expired or has already been used.', 401);
  let verified: Record<string, unknown>;
  try {
    verified = await appleRequest(env, 'token', { grant_type: 'refresh_token', refresh_token: await decrypt(current.encrypted_grant, env.SESSION_ENCRYPTION_KEY, current.user_id) });
    assert(typeof verified.id_token === 'string', 'APPLE_EXCHANGE', 'Apple did not return a valid identity token.', 401);
    const { payload } = await verifyAppleToken(env, verified.id_token);
    assert(payload.sub === current.subject, 'APPLE_EXCHANGE', 'Apple identity no longer matches this account.', 401);
  } catch (error) {
    if (error instanceof AppError && error.retryable) throw error;
    await env.DB.prepare('DELETE FROM sessions WHERE user_id=?').bind(current.user_id).run();
    throw new AppError(401, 'APPLE_REVOKED', 'Apple authorization ended. Sign in again.');
  }
  if (typeof verified.refresh_token === 'string') {
    await env.DB.prepare('UPDATE apple_identities SET encrypted_grant=? WHERE user_id=?').bind(await encrypt(verified.refresh_token, env.SESSION_ENCRYPTION_KEY, current.user_id), current.user_id).run();
  }
  const accessToken = randomToken(), refreshToken = randomToken(), expires = Date.now() + ACCESS_TTL;
  const row = await env.DB.prepare('UPDATE sessions SET access_hash=?,refresh_hash=?,access_expires_at=?,refresh_expires_at=? WHERE refresh_hash=? AND refresh_expires_at>? AND user_id IN(SELECT id FROM users WHERE deleting=0) RETURNING user_id').bind(await sha256(accessToken), await sha256(refreshToken), expires, Date.now() + REFRESH_TTL, await sha256(oldToken), Date.now()).first<{ user_id: string }>();
  assert(row, 'UNAUTHENTICATED', 'Refresh token has expired or has already been used.', 401);
  const user = await env.DB.prepare('SELECT id,display_name FROM users WHERE id=? AND deleting=0').bind(row.user_id).first<{ id: string; display_name: string }>();
  assert(user, 'UNAUTHENTICATED', 'Account is no longer active.', 401);
  return { user: { id: user.id, displayName: user.display_name }, accessToken, refreshToken, expiresAt: new Date(expires).toISOString() };
}
export async function logout(env: Env, principal: Principal, value: unknown): Promise<void> {
  const { refreshToken } = parse(z.strictObject({ refreshToken: z.string().regex(/^[a-f0-9]{64}$/) }), value);
  await env.DB.prepare('DELETE FROM sessions WHERE user_id=? AND (id=? OR refresh_hash=?)').bind(principal.id, principal.sessionId, await sha256(refreshToken)).run();
}
export async function registerTarget(env: Env, userId: string, tripId: string): Promise<void> {
  const user = await env.DB.prepare('SELECT id FROM users WHERE id=? AND deleting=0').bind(userId).first();
  assert(user, 'ACCOUNT_DELETING', 'Account is no longer active.', 403);
  const targets = await env.DB.prepare('SELECT count(*) AS count FROM user_trip_targets WHERE user_id=? AND trip_id<>?').bind(userId, tripId).first<{ count: number }>();
  assert(targets && targets.count < 500, 'TRIP_LIMIT', 'An account can sync at most 500 trips.');
  await env.DB.prepare('INSERT OR IGNORE INTO user_trip_targets(user_id,trip_id) SELECT id,? FROM users WHERE id=? AND deleting=0').bind(tripId, userId).run();
}
export async function deleteAccount(env: Env, userId: string): Promise<void> {
  await env.DB.batch([
    env.DB.prepare('INSERT OR IGNORE INTO deletion_jobs(user_id,encrypted_grant,created_at) SELECT u.id,a.encrypted_grant,? FROM users u LEFT JOIN apple_identities a ON a.user_id=u.id WHERE u.id=?').bind(new Date().toISOString(), userId),
    env.DB.prepare('UPDATE users SET deleting=1,display_name=? WHERE id=?').bind('Deleted account', userId),
    env.DB.prepare('DELETE FROM sessions WHERE user_id=?').bind(userId),
  ]);
}
export async function processDeletions(env: Env): Promise<void> {
  const jobs = await env.DB.prepare('SELECT * FROM deletion_jobs WHERE next_attempt_at<=? ORDER BY created_at LIMIT 10').bind(Date.now()).all<{ user_id: string; encrypted_grant: string | null; cursor: string; attempts: number }>();
  for (const job of jobs.results) {
    try {
      const targets = await env.DB.prepare('SELECT trip_id FROM user_trip_targets WHERE user_id=? AND trip_id>? ORDER BY trip_id LIMIT 50').bind(job.user_id, job.cursor).all<{ trip_id: string }>();
      for (const target of targets.results) {
        await env.TRIPS.getByName(target.trip_id).removeAccount(job.user_id);
        await env.DB.prepare('UPDATE deletion_jobs SET cursor=? WHERE user_id=?').bind(target.trip_id, job.user_id).run();
      }
      if (targets.results.length === 50) continue;
      if (job.encrypted_grant) {
        const grant = await decrypt(job.encrypted_grant, env.SESSION_ENCRYPTION_KEY, job.user_id);
        await appleRequest(env, 'revoke', { token: grant, token_type_hint: 'refresh_token' });
      }
      await env.DB.batch([
        env.DB.prepare('DELETE FROM user_trips WHERE user_id=?').bind(job.user_id),
        env.DB.prepare('DELETE FROM user_trip_targets WHERE user_id=?').bind(job.user_id),
        env.DB.prepare('DELETE FROM apple_identities WHERE user_id=?').bind(job.user_id),
        env.DB.prepare('DELETE FROM sessions WHERE user_id=?').bind(job.user_id),
        env.DB.prepare('DELETE FROM users WHERE id=?').bind(job.user_id),
        env.DB.prepare('DELETE FROM deletion_jobs WHERE user_id=?').bind(job.user_id),
      ]);
    } catch {
      const attempts = job.attempts + 1;
      await env.DB.prepare('UPDATE deletion_jobs SET attempts=?,next_attempt_at=? WHERE user_id=?').bind(attempts, Date.now() + Math.min(86_400_000, 60_000 * 2 ** Math.min(attempts, 10)), job.user_id).run();
      console.error(JSON.stringify({ event: 'account_deletion_retry', attempts }));
    }
  }
}
