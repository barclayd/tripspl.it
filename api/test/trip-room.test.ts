import { env } from 'cloudflare:workers';
import { evictDurableObject, runDurableObjectAlarm, runInDurableObject } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import type { Operation, SyncResponse, TripSnapshot } from '../src/types/contract';
import { create, draft, expense, addExpense, request, session } from './fixtures';

async function sync(trip: TripSnapshot, user: Awaited<ReturnType<typeof session>>, operations: Operation[]): Promise<SyncResponse> {
  const response = await request(`/trips/${trip.id}/sync`, user, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations });
  expect(response.status).toBe(200); return response.json<SyncResponse>();
}
async function join(trip: TripSnapshot, owner: Awaited<ReturnType<typeof session>>, member: Awaited<ReturnType<typeof session>>, travellerId = 'b'): Promise<void> {
  const invitation = await (await request(`/trips/${trip.id}/invites`, owner, { travellerId })).json<{ id: string; token: string }>();
  const response = await request(`/trips/${trip.id}/invites/${invitation.id}/accept`, member, { token: invitation.token });
  expect(response.status).toBe(200);
}
describe('authoritative trip operations in SQLite', () => {
  it('composes independent additions, persists receipts through eviction, rejects mutated IDs', async () => {
    const owner = await session(), trip = await create(owner), operation = addExpense(trip);
    const first = await sync(trip, owner, [operation]); expect(first.results[0]?.status).toBe('accepted');
    const stub = env.TRIPS.getByName(trip.id);
    await evictDurableObject(stub);
    const replay = await sync(trip, owner, [operation, addExpense(trip)]);
    expect(replay.results.map(r => r.status)).toEqual(['duplicate', 'accepted']); expect(replay.snapshot?.expenses).toHaveLength(2);
    const changed = { ...operation, payload: { ...expense(operation.entityId), amountMinor: '10001' } } as Operation;
    const rejected = await sync(trip, owner, [changed]); expect(rejected.results[0]?.code).toBe('OPERATION_REUSED');
    const counts = await runInDurableObject(stub, (_instance, state) => state.storage.sql.exec<{ n: number }>('SELECT count(*) AS n FROM operation_receipts').one().n);
    expect(counts).toBe(3);
  });
  it('returns conflicts without losing drafts, persists tombstones against stale restoration', async () => {
    const owner = await session(), trip = await create(owner), original = expense();
    const added = await sync(trip, owner, [addExpense(trip, original)]); const saved = added.snapshot!.expenses[0]!;
    const edit: Operation = { id: crypto.randomUUID(), syncEpoch: trip.syncEpoch, type: 'expense.upsert', entityId: saved.id, expectedRevision: saved.revision, payload: { ...saved, title: 'Changed dinner' } };
    expect((await sync(trip, owner, [edit])).results[0]?.status).toBe('accepted');
    expect((await sync(trip, owner, [{ ...edit, id: crypto.randomUUID() }])).results[0]?.code).toBe('REVISION_CONFLICT');
    const deletion: Operation = { id: crypto.randomUUID(), syncEpoch: trip.syncEpoch, type: 'expense.delete', entityId: saved.id, expectedRevision: 2, payload: null };
    expect((await sync(trip, owner, [deletion])).results[0]?.status).toBe('accepted');
    await evictDurableObject(env.TRIPS.getByName(trip.id));
    const restore = await sync(trip, owner, [addExpense(trip, original)]);
    expect(restore.results[0]?.code).toBe('ENTITY_DELETED'); expect(restore.snapshot?.expenses).toEqual([]);
  });
  it('checks membership before replay, enforces owner settings and member edits', async () => {
    const owner = await session(), member = await session(), stranger = await session(), trip = await create(owner);
    expect((await request(`/trips/${trip.id}`, stranger)).status).toBe(403);
    await join(trip, owner, member);
    const operation = addExpense(trip);
    expect((await sync(trip, member, [operation])).results[0]?.status).toBe('accepted');
    const settings: Operation = { id: crypto.randomUUID(), syncEpoch: trip.syncEpoch, type: 'trip.archive', entityId: trip.id, expectedRevision: 4, payload: { archived: true } };
    expect((await request(`/trips/${trip.id}/sync`, member, { cursor: 1, syncEpoch: trip.syncEpoch, operations: [settings] })).status).toBe(403);
    expect((await request(`/trips/${trip.id}/members/b`, owner, undefined, 'DELETE')).status).toBe(200);
    expect((await request(`/trips/${trip.id}/sync`, member, { cursor: 1, syncEpoch: trip.syncEpoch, operations: [operation] })).status).toBe(403);
    const snapshot = await (await request(`/trips/${trip.id}`, owner)).json<TripSnapshot>(); expect(snapshot.expenses).toHaveLength(1);
  });
  it('keeps receipts and writes atomic when a graph invariant fails', async () => {
    const owner = await session(), trip = await create(owner), broken = expense(); broken.attachment.id = 'missing';
    const failed = await sync(trip, owner, [addExpense(trip, broken)]);
    expect(failed.results[0]?.status).toBe('rejected'); expect(failed.snapshot?.revision).toBe(1);
    const state = await runInDurableObject(env.TRIPS.getByName(trip.id), (_instance, state) => ({ receipts: state.storage.sql.exec<{ n: number }>('SELECT count(*) AS n FROM operation_receipts').one().n, entities: state.storage.sql.exec<{ n: number }>("SELECT count(*) AS n FROM entities WHERE kind='expense'").one().n }));
    expect(state).toEqual({ receipts: 1, entities: 0 });
  });
  it('rejects stale epochs and referenced itinerary shifts, locks home currency after records', async () => {
    const owner = await session(), trip = await create(owner);
    expect((await sync(trip, owner, [{ ...addExpense(trip), syncEpoch: 'restored-old-epoch' }])).results[0]?.code).toBe('SYNC_EPOCH');
    const added = await sync(trip, owner, [addExpense(trip)]), current = added.snapshot!;
    const { name, startsOn, timeZone, homeCurrency, budgetMinor, stops, days, legs } = current;
    const operation: Operation = { id: crypto.randomUUID(), syncEpoch: trip.syncEpoch, type: 'trip.update', entityId: trip.id, expectedRevision: current.revision, payload: { name, startsOn, timeZone, homeCurrency: 'USD', budgetMinor, stops, days, legs } };
    expect((await sync(trip, owner, [operation])).results[0]?.code).toBe('HOME_CURRENCY_LOCKED');
    operation.id = crypto.randomUUID(); operation.payload.homeCurrency = homeCurrency; operation.payload.startsOn = '2026-10-02'; operation.payload.days = days.map(d => ({ ...d, date: d.id === 'day1' ? '2026-10-02' : '2026-10-03' }));
    expect((await sync(trip, owner, [operation])).results[0]?.code).toBe('REFERENCED_ITINERARY');
  });
  it('retries directory projection after D1 failure and never lets the index grant access', async () => {
    const owner = await session(), stranger = await session(), trip = await create(owner), stub = env.TRIPS.getByName(trip.id);
    await env.DB.prepare('ALTER TABLE user_trips RENAME TO user_trips_unavailable').run();
    await runInDurableObject(stub, async (instance) => { try { await instance.flushDirectory(); throw new Error('Expected projection failure'); } catch (error) { expect(String(error)).toContain('user_trips'); } });
    const queued = await runInDurableObject(stub, (_instance, state) => state.storage.sql.exec<{ n: number }>('SELECT count(*) AS n FROM directory_outbox').one().n); expect(queued).toBe(1);
    await env.DB.prepare('ALTER TABLE user_trips_unavailable RENAME TO user_trips').run();
    await runDurableObjectAlarm(stub);
    expect(await env.DB.prepare('SELECT active FROM user_trips WHERE user_id=?').bind(owner.user.id).first()).toEqual({ active: 1 });
    await env.DB.prepare('INSERT INTO user_trip_targets(user_id,trip_id) VALUES(?,?)').bind(stranger.user.id, trip.id).run();
    const listed = await (await request('/trips', stranger)).json<{ trips: TripSnapshot[] }>(); expect(listed.trips).toEqual([]);
  });
  it('creation replays with the same immutable operation after uncertain acknowledgement', async () => {
    const owner = await session(), original = draft(), operationId = crypto.randomUUID();
    const one = await request('/trips', owner, { operationId, trip: original }); expect(one.status).toBe(201);
    const replay = await request('/trips', owner, { operationId, trip: original }); expect(replay.status).toBe(201);
    const changed = await request('/trips', owner, { operationId, trip: { ...original, name: 'Different' } }); expect(changed.status).toBe(409);
  });
  it('concurrent retries create one trip and invitations reject wrong, expired and revoked secrets', async () => {
    const owner = await session(), member = await session(), original = draft(), operationId = crypto.randomUUID();
    const responses = await Promise.all([request('/trips', owner, { operationId, trip: original }), request('/trips', owner, { operationId, trip: original })]);
    expect(responses.map(r => r.status)).toEqual([201, 201]);
    const trip = await responses[0]!.json<TripSnapshot>();
    const invite = await (await request(`/trips/${trip.id}/invites`, owner, { travellerId: 'b' })).json<{ id: string; token: string; url: string | null }>();
    expect(invite.url).toBeNull();
    expect((await request(`/trips/${trip.id}/invites/${invite.id}/accept`, member, { token: 'a'.repeat(64) })).status).toBe(403);
    expect(await env.DB.prepare('SELECT count(*) AS n FROM user_trip_targets WHERE user_id=?').bind(member.user.id).first()).toEqual({ n: 0 });
    await runInDurableObject(env.TRIPS.getByName(trip.id), (_instance, state) => { state.storage.sql.exec('UPDATE invites SET expires_at=0'); });
    expect((await request(`/trips/${trip.id}/invites/${invite.id}/accept`, member, { token: invite.token })).status).toBe(403);
    const another = await (await request(`/trips/${trip.id}/invites`, owner, { travellerId: 'b' })).json<{ id: string; token: string }>();
    await request(`/trips/${trip.id}/invites/${another.id}`, owner, undefined, 'DELETE');
    expect((await request(`/trips/${trip.id}/invites/${another.id}/accept`, member, { token: another.token })).status).toBe(403);
  });
  it('deletes a trip for every traveller, owner only and idempotently, and frees their trip slots', async () => {
    const owner = await session(), member = await session(), original = draft(), operationId = crypto.randomUUID();
    const trip = await (await request('/trips', owner, { operationId, trip: original })).json<TripSnapshot>();
    await join(trip, owner, member); await sync(trip, owner, [addExpense(trip)]);
    const targets = async () => (await env.DB.prepare('SELECT count(*) AS n FROM user_trip_targets WHERE trip_id=?').bind(trip.id).first<{ n: number }>())!.n;
    expect(await targets()).toBe(2);
    const forbidden = await request(`/trips/${trip.id}`, member, undefined, 'DELETE');
    expect(forbidden.status).toBe(403); expect((await forbidden.json<{ error: { code: string } }>()).error.code).toBe('OWNER_REQUIRED');
    expect((await request(`/trips/${trip.id}`, owner, undefined, 'DELETE')).status).toBe(200);
    expect((await request(`/trips/${trip.id}`, owner, undefined, 'DELETE')).status).toBe(200);
    expect(await targets()).toBe(0);
    for (const user of [owner, member]) {
      const read = await request(`/trips/${trip.id}`, user);
      expect(read.status).toBe(404); expect((await read.json<{ error: { code: string } }>()).error.code).toBe('TRIP_NOT_FOUND');
      expect((await request(`/trips/${trip.id}/sync`, user, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations: [addExpense(trip)] })).status).toBe(404);
    }
    // A device that never heard the first create acknowledged can't bring the trip back.
    expect((await request('/trips', owner, { operationId, trip: original })).status).toBe(404);
    expect((await request('/trips', owner, { operationId: crypto.randomUUID(), trip: original })).status).toBe(409);
    expect((await (await request('/trips', owner)).json<{ trips: TripSnapshot[] }>()).trips).toEqual([]);
    expect(await targets()).toBe(0);
    const stored = await runInDurableObject(env.TRIPS.getByName(trip.id), (_instance, state) => ({
      live: state.storage.sql.exec<{ n: number }>('SELECT count(*) AS n FROM entities WHERE data IS NOT NULL').one().n,
      changes: state.storage.sql.exec<{ n: number }>('SELECT count(*) AS n FROM changes').one().n,
    }));
    expect(stored).toEqual({ live: 0, changes: 0 });
    await runDurableObjectAlarm(env.TRIPS.getByName(trip.id));
    expect(await env.DB.prepare('SELECT count(*) AS n FROM user_trips WHERE trip_id=? AND active=1').bind(trip.id).first()).toEqual({ n: 0 });
  });
});
