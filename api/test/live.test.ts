import { env } from 'cloudflare:workers';
import { evictDurableObject, runInDurableObject } from 'cloudflare:test';
import { expect, it } from 'vitest';
import { addExpense, create, request, session } from './fixtures';
import type { TripSnapshot } from '../../contracts/tripsplit-v1';

it('hibernates authenticated live subscriptions, sends hints and closes revoked members', async () => {
  const owner = await session(), member = await session(), trip = await create(owner);
  const invite = await (await request(`/trips/${trip.id}/invites`, owner, { travellerId: 'b' })).json<{ id: string; token: string }>();
  expect((await request(`/trips/${trip.id}/invites/${invite.id}/accept`, member, { token: invite.token })).status).toBe(200);
  const response = await import('cloudflare:workers').then(({ exports }) => exports.default.fetch(`https://api.example.com/v1/trips/${trip.id}/live`, { headers: { Upgrade: 'websocket', authorization: `Bearer ${member.accessToken}` } }));
  expect(response.status).toBe(101); const socket = response.webSocket!; socket.accept();
  await evictDurableObject(env.TRIPS.getByName(trip.id));
  const changed = new Promise<string>(resolve => socket.addEventListener('message', event => resolve(String(event.data)), { once: true }));
  await request(`/trips/${trip.id}/sync`, owner, { cursor: 1, syncEpoch: trip.syncEpoch, operations: [addExpense(trip)] });
  expect(JSON.parse(await changed)).toMatchObject({ type: 'changed', syncEpoch: trip.syncEpoch });
  const closed = new Promise<number>(resolve => socket.addEventListener('close', event => resolve(event.code), { once: true }));
  await request(`/trips/${trip.id}/members/b`, owner, undefined, 'DELETE'); expect(await closed).toBe(1008);
});

it('rolls back ledger writes when the receipt cannot commit and recovers from a changed server epoch', async () => {
  const owner = await session(), trip = await create(owner), stub = env.TRIPS.getByName(trip.id), op = addExpense(trip);
  await runInDurableObject(stub, (_instance, state) => { state.storage.sql.exec("CREATE TRIGGER reject_receipt BEFORE INSERT ON operation_receipts BEGIN SELECT RAISE(ABORT, 'injected failure'); END"); });
  const failed = await request(`/trips/${trip.id}/sync`, owner, { cursor: 1, syncEpoch: trip.syncEpoch, operations: [op] }); expect(failed.status).toBe(500);
  const unchanged = await (await request(`/trips/${trip.id}`, owner)).json<TripSnapshot>(); expect(unchanged.revision).toBe(1); expect(unchanged.expenses).toEqual([]);
  await runInDurableObject(stub, (_instance, state) => { state.storage.sql.exec('DROP TRIGGER reject_receipt'); state.storage.sql.exec('UPDATE trip SET recovery_epoch=0,epoch=?,revision=1', crypto.randomUUID()); });
  await env.DB.prepare('INSERT INTO user_trips(user_id,trip_id,revision,recovery_epoch,active,updated_at) VALUES(?,?,99,0,0,?)').bind(owner.user.id, trip.id, new Date().toISOString()).run();
  const recovered = await (await request(`/trips/${trip.id}`, owner)).json<TripSnapshot>(); expect(recovered.revision).toBe(2); expect(recovered.syncEpoch).not.toBe(trip.syncEpoch);
  const stale = await (await request(`/trips/${trip.id}/sync`, owner, { cursor: 1, syncEpoch: trip.syncEpoch, operations: [op] })).json<{ results: { code: string }[] }>(); expect(stale.results[0]?.code).toBe('SYNC_EPOCH');
  await stub.flushDirectory();
  expect(await env.DB.prepare('SELECT revision,recovery_epoch,active FROM user_trips WHERE user_id=?').bind(owner.user.id).first()).toEqual({ revision: 2, recovery_epoch: 1, active: 1 });
});
