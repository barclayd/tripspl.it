import { importPKCS8, SignJWT } from 'jose';
import { assert } from '../utils/errors';

export type PushMessage = { title: string; body: string; category: string; threadId: string; collapseId: string; data: Record<string, string> };
export type APNsConfig = { teamId: string; keyId: string; privateKey: string; topic: string };
type Device = { token: string; environment: 'sandbox' | 'production' };

const HOSTS = { sandbox: 'https://api.sandbox.push.apple.com', production: 'https://api.push.apple.com' } as const;
/** Each account keeps its most recent devices; older ones stop getting buzzed. */
const DEVICE_LIMIT = 10;
/** Apple accepts a provider token for an hour and throttles new ones within 20 minutes. */
const TOKEN_TTL = 40 * 60_000;
// Gone tokens: uninstalled, or registered against the other environment or app.
const STALE = new Set(['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered']);

/**
 * APNs is optional. Without `APNS_KEY_ID` the API still records nudges but can't buzz anyone.
 * `APNS_PRIVATE_KEY` is an optional secret: when the Sign in with Apple key also has APNs
 * enabled, set `APNS_KEY_ID` to `APPLE_KEY_ID` and that key is used.
 */
export function apnsConfig(env: Env): APNsConfig | null {
  const keyId = env.APNS_KEY_ID, own = (env as Env & { APNS_PRIVATE_KEY?: string }).APNS_PRIVATE_KEY;
  const privateKey = own || (keyId && keyId === env.APPLE_KEY_ID ? env.APPLE_PRIVATE_KEY : '');
  if (!keyId || !privateKey || !env.APPLE_TEAM_ID || !env.APPLE_AUDIENCE) return null;
  return { teamId: env.APPLE_TEAM_ID, keyId, privateKey, topic: env.APPLE_AUDIENCE };
}

export async function registerDevice(env: Env, userId: string, device: Device): Promise<void> {
  const [registered] = await env.DB.batch<{ token: string }>([
    env.DB.prepare('INSERT INTO device_tokens(token,user_id,environment,updated_at) SELECT ?,id,?,? FROM users WHERE id=? AND deleting=0 ON CONFLICT(token) DO UPDATE SET user_id=excluded.user_id,environment=excluded.environment,updated_at=excluded.updated_at RETURNING token').bind(device.token, device.environment, Date.now(), userId),
    env.DB.prepare('DELETE FROM device_tokens WHERE user_id=? AND token NOT IN (SELECT token FROM device_tokens WHERE user_id=? ORDER BY updated_at DESC, rowid DESC LIMIT ?)').bind(userId, userId, DEVICE_LIMIT),
  ]);
  assert(registered?.results.length, 'ACCOUNT_DELETING', 'Account is no longer active.', 403);
}

export async function removeDevice(env: Env, userId: string, token: string): Promise<void> {
  await env.DB.prepare('DELETE FROM device_tokens WHERE token=? AND user_id=?').bind(token, userId).run();
}

let provider: { keyId: string; token: string; expires: number } | undefined;
async function providerToken(config: APNsConfig): Promise<string> {
  if (provider?.keyId === config.keyId && provider.expires > Date.now()) return provider.token;
  const key = await importPKCS8(config.privateKey.replace(/\\n/g, '\n'), 'ES256');
  const token = await new SignJWT({}).setProtectedHeader({ alg: 'ES256', kid: config.keyId }).setIssuer(config.teamId).setIssuedAt().sign(key);
  provider = { keyId: config.keyId, token, expires: Date.now() + TOKEN_TTL };
  return token;
}

/**
 * Buzzes every device the account registered, best effort: failures are logged, never thrown,
 * and tokens APNs says are gone are removed. Logs carry outcomes only, never tokens or text.
 */
export async function push(env: Env, userId: string, message: PushMessage, config = apnsConfig(env)): Promise<void> {
  if (!config) { console.log(JSON.stringify({ event: 'push_skipped', category: message.category, reason: 'not_configured' })); return; }
  try {
    const devices = (await env.DB.prepare('SELECT token,environment FROM device_tokens WHERE user_id=?').bind(userId).all<Device>()).results;
    if (!devices.length) { console.log(JSON.stringify({ event: 'push_skipped', category: message.category, reason: 'no_devices' })); return; }
    const authorization = `bearer ${await providerToken(config)}`;
    const payload = JSON.stringify({ ...message.data, aps: { alert: { title: message.title, body: message.body }, sound: 'default', category: message.category, 'thread-id': message.threadId } });
    const outcomes = await Promise.all(devices.map(async device => {
      try {
        const response = await fetch(`${HOSTS[device.environment]}/3/device/${device.token}`, {
          method: 'POST', body: payload,
          headers: { authorization, 'content-type': 'application/json', 'apns-topic': config.topic, 'apns-push-type': 'alert', 'apns-priority': '10', 'apns-expiration': String(Math.floor(Date.now() / 1000) + 86_400), 'apns-collapse-id': message.collapseId },
        });
        if (response.ok) return 'sent';
        const reason = (await response.json<{ reason?: string }>().catch(() => null))?.reason ?? `http_${response.status}`;
        if (response.status === 410 || STALE.has(reason)) {
          await env.DB.prepare('DELETE FROM device_tokens WHERE token=? AND user_id=?').bind(device.token, userId).run();
          return 'removed';
        }
        return reason;
      } catch { return 'network'; }
    }));
    const counts: Record<string, number> = {};
    for (const outcome of outcomes) counts[outcome] = (counts[outcome] ?? 0) + 1;
    console.log(JSON.stringify({ event: 'push_sent', category: message.category, outcomes: counts }));
  } catch (error) {
    console.error(JSON.stringify({ event: 'push_failed', category: message.category, kind: error instanceof Error ? error.name : 'unknown' }));
  }
}
