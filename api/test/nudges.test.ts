import { env } from 'cloudflare:workers';
import { runInDurableObject } from 'cloudflare:test';
import { decodeJwt, decodeProtectedHeader, exportPKCS8, generateKeyPair } from 'jose';
import { describe, expect, it, vi } from 'vitest';
import type { TripRoom } from '../src/durable-objects/trip-room';
import { deleteAccount } from '../src/services/auth';
import { push, type PushMessage } from '../src/services/push';
import type { NudgeResult, Session, TripSnapshot } from '../src/types/contract';
import { addExpense, create, request, session } from './fixtures';

async function join(trip: TripSnapshot, owner: Session, member: Session, travellerId: string): Promise<void> {
  const invitation = await (await request(`/trips/${trip.id}/invites`, owner, { travellerId })).json<{ id: string; token: string }>();
  expect((await request(`/trips/${trip.id}/invites/${invitation.id}/accept`, member, { token: invitation.token })).status).toBe(200);
}
/** Alice pays £100 for all three, so Bob and Charlie each owe her £33.33. Bob has an account. */
async function owed(): Promise<{ alice: Session; bob: Session; trip: TripSnapshot }> {
  const alice = await session('Alice'), bob = await session('Bob'), trip = await create(alice);
  const sync = await request(`/trips/${trip.id}/sync`, alice, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations: [addExpense(trip)] });
  expect(sync.status).toBe(200);
  await join(trip, alice, bob, 'b');
  return { alice, bob, trip };
}
const nudge = (trip: TripSnapshot, user: Session, travellerId: string) => request(`/trips/${trip.id}/nudges`, user, { travellerId });
const code = async (response: Response) => (await response.json<{ error: { code: string } }>()).error.code;
const token = (seed: string) => seed.repeat(64).slice(0, 64);
function tokyoToday(): string {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Tokyo', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(Date.now()).map(part => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
}

describe('nudges', () => {
  it('nudges a traveller who owes you once per trip day', async () => {
    const { alice, trip } = await owed();
    const first = await nudge(trip, alice, 'b');
    expect(first.status).toBe(200);
    expect(await first.json<NudgeResult>()).toEqual({ status: 'sent', nudgedOn: tokyoToday() });
    const again = await nudge(trip, alice, 'b');
    expect(again.status).toBe(429); expect(await code(again)).toBe('NUDGE_LIMIT');
  });
  it("can't reach a traveller without an account, and doesn't use up their day", async () => {
    const { alice, trip } = await owed();
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const response = await nudge(trip, alice, 'c');
      expect(response.status).toBe(200);
      expect(await response.json<NudgeResult>()).toEqual({ status: 'notJoined', nudgedOn: tokyoToday() });
    }
  });
  it('only nudges someone else on the trip who owes you', async () => {
    const { alice, bob, trip } = await owed(), stranger = await session();
    const reverse = await nudge(trip, bob, 'a');
    expect(reverse.status).toBe(409); expect(await code(reverse)).toBe('NOTHING_OWED');
    expect(await code(await nudge(trip, alice, 'a'))).toBe('TRAVELLER');
    expect(await code(await nudge(trip, alice, 'nobody'))).toBe('TRAVELLER');
    expect((await nudge(trip, stranger, 'b')).status).toBe(403);
    expect((await request(`/trips/${trip.id}/nudges/b`, alice, { travellerId: 'b' })).status).toBe(404);
  });
  it('tells the recipient who nudged them and what they owe', async () => {
    const { alice, bob, trip } = await owed();
    const result = await runInDurableObject(env.TRIPS.getByName(trip.id), (room: TripRoom) => room.nudge(alice.user.id, 'b'));
    expect(result.push).toEqual({
      userId: bob.user.id,
      message: { title: 'Alice nudged you', body: 'You owe Alice £33.33 for Japan.', category: 'tripsplit.nudge', threadId: trip.id, collapseId: `nudge.${trip.id}.a`, data: { trip: trip.id, traveller: 'a' } },
    });
  });
});

describe('devices and push', () => {
  const message: PushMessage = { title: 'Alice nudged you', body: 'You owe Alice £33.33 for Japan.', category: 'tripsplit.nudge', threadId: 't', collapseId: 'nudge.t.a', data: { trip: 't' } };
  const devices = async (userId: string) => (await env.DB.prepare('SELECT token,environment FROM device_tokens WHERE user_id=? ORDER BY token').bind(userId).all()).results;

  it('registers, moves and removes device tokens', async () => {
    const alice = await session(), bob = await session();
    expect((await request('/me/devices', alice, { token: token('a'), environment: 'sandbox' })).status).toBe(200);
    expect((await request('/me/devices', alice, { token: 'not-a-token', environment: 'sandbox' })).status).toBe(400);
    expect((await request('/me/devices', alice, { token: token('b'), environment: 'staging' })).status).toBe(400);
    expect(await devices(alice.user.id)).toEqual([{ token: token('a'), environment: 'sandbox' }]);
    // The same phone signed in to another account.
    expect((await request('/me/devices', bob, { token: token('a'), environment: 'production' })).status).toBe(200);
    expect(await devices(alice.user.id)).toEqual([]);
    expect((await request('/me/devices', alice, { token: token('a') }, 'DELETE')).status).toBe(200);
    expect(await devices(bob.user.id)).toHaveLength(1);
    expect((await request('/me/devices', bob, { token: token('a') }, 'DELETE')).status).toBe(200);
    expect(await devices(bob.user.id)).toEqual([]);
  });
  it('keeps the ten most recent devices, and drops them all with the account', async () => {
    const alice = await session();
    const hex = '0123456789ab';
    for (const seed of hex) {
      expect((await request('/me/devices', alice, { token: token(seed), environment: 'production' })).status).toBe(200);
    }
    expect((await devices(alice.user.id)).map(row => row.token)).toEqual([...hex.slice(2)].map(token));
    await deleteAccount(env, alice.user.id);
    expect(await devices(alice.user.id)).toEqual([]);
  });
  it('sends to each device and forgets tokens APNs has dropped', async () => {
    const alice = await session();
    await request('/me/devices', alice, { token: token('a'), environment: 'sandbox' });
    await request('/me/devices', alice, { token: token('b'), environment: 'production' });
    const { privateKey } = await generateKeyPair('ES256', { extractable: true });
    const config = { teamId: 'TEAM123456', keyId: 'KEY1234567', privateKey: await exportPKCS8(privateKey), topic: 'it.tripspl.TripSplit' };
    const requests: Request[] = [];
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init) => {
      const sent = new Request(input, init); requests.push(sent);
      return sent.url.includes(token('b')) ? Response.json({ reason: 'Unregistered' }, { status: 410 }) : new Response(null, { status: 200 });
    });
    await push(env, alice.user.id, message, config);
    expect(requests.map(sent => sent.url).sort()).toEqual([`https://api.push.apple.com/3/device/${token('b')}`, `https://api.sandbox.push.apple.com/3/device/${token('a')}`]);
    const sent = requests[0]!;
    expect(sent.headers.get('apns-topic')).toBe('it.tripspl.TripSplit');
    expect(sent.headers.get('apns-push-type')).toBe('alert');
    expect(sent.headers.get('apns-collapse-id')).toBe('nudge.t.a');
    const jwt = sent.headers.get('authorization')!.replace(/^bearer /, '');
    expect(decodeProtectedHeader(jwt)).toEqual({ alg: 'ES256', kid: 'KEY1234567' });
    expect(decodeJwt(jwt).iss).toBe('TEAM123456');
    expect(await sent.json()).toEqual({ trip: 't', aps: { alert: { title: message.title, body: message.body }, sound: 'default', category: 'tripsplit.nudge', 'thread-id': 't' } });
    expect(await devices(alice.user.id)).toEqual([{ token: token('a'), environment: 'sandbox' }]);
  });
  it('skips quietly without an APNs key', async () => {
    const alice = await session(), fetch = vi.spyOn(globalThis, 'fetch');
    await request('/me/devices', alice, { token: token('a'), environment: 'sandbox' });
    await push(env, alice.user.id, message);
    expect(fetch).not.toHaveBeenCalled();
  });
});
