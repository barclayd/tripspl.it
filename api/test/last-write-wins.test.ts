import { env } from 'cloudflare:workers';
import { evictDurableObject } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import type { Operation, Session, SyncResponse, TripSnapshot } from '../src/types/contract';
import { addExpense, create, expense, request, session } from './fixtures';

async function sync(trip: TripSnapshot, owner: Session, operations: Operation[]): Promise<SyncResponse> {
  const response = await request(`/trips/${trip.id}/sync`, owner, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations });
  expect(response.status).toBe(200); return response.json<SyncResponse>();
}
function edit(trip: TripSnapshot, editedAt: number, title: string, id = 'dinner'): Operation {
  return { ...addExpense(trip, { ...expense(id), title }), editedAt };
}

describe('offline last-write-wins', () => {
  it('converges in either delivery order, across eviction and lost acknowledgements', async () => {
    for (const reverse of [false, true]) {
      const owner = await session(), trip = await create(owner);
      const older = edit(trip, 100, 'Earlier'), newer = edit(trip, 200, 'Later');
      expect((await sync(trip, owner, [reverse ? newer : older])).results[0]?.status).toBe('accepted');
      await evictDurableObject(env.TRIPS.getByName(trip.id));
      const second = await sync(trip, owner, [reverse ? older : newer]);
      expect(second.results[0]?.status).toBe(reverse ? 'superseded' : 'accepted');
      expect(second.snapshot?.expenses[0]?.title).toBe('Later');
      expect(second.snapshot?.writeClock).toBe(200);
      const replay = await sync(trip, owner, [older, newer]);
      expect(replay.results.map(r => r.status)).toEqual(['duplicate', 'duplicate']);
      expect(replay.snapshot?.expenses[0]?.title).toBe('Later');
      expect((await sync(trip, owner, [{ ...older, editedAt: 300 }])).results[0]?.code).toBe('OPERATION_REUSED');
    }
  });
  it('breaks equal clocks by operation ID consistently', async () => {
    const owner = await session(), trip = await create(owner);
    await sync(trip, owner, [{ ...edit(trip, 100, 'Higher'), id: 'z' }]);
    const result = await sync(trip, owner, [{ ...edit(trip, 100, 'Lower'), id: 'a' }]);
    expect(result.results[0]?.status).toBe('superseded');
    expect(result.snapshot?.expenses[0]?.title).toBe('Higher');
  });
  it('retains deletion clocks even when a delete arrives before its insert', async () => {
    const owner = await session(), trip = await create(owner);
    const deletion: Operation = { id: 'delete', type: 'expense.delete', entityId: 'dinner', syncEpoch: trip.syncEpoch, expectedRevision: 0, editedAt: 200, payload: null };
    expect((await sync(trip, owner, [deletion])).results[0]?.status).toBe('accepted');
    await evictDurableObject(env.TRIPS.getByName(trip.id));
    const older = await sync(trip, owner, [edit(trip, 100, 'Old dinner')]);
    expect(older.results[0]?.status).toBe('superseded');
    expect(older.snapshot?.expenses).toEqual([]);
    expect((await sync(trip, owner, [edit(trip, 300, 'Restored')])).snapshot?.expenses[0]?.title).toBe('Restored');
  });
  it('merges separate records, archive state, settings and day locations independently', async () => {
    const owner = await session(), trip = await create(owner);
    const { name, startsOn, timeZone, homeCurrency, budgetMinor, stops, days, legs } = trip;
    const settings: Operation = { id: 'settings', type: 'trip.update', entityId: trip.id, syncEpoch: trip.syncEpoch, expectedRevision: 1, editedAt: 100, payload: { name: name + ' edited', startsOn, timeZone, homeCurrency, budgetMinor, stops, days, legs } };
    const archive: Operation = { id: 'archive', type: 'trip.archive', entityId: trip.id, syncEpoch: trip.syncEpoch, expectedRevision: 1, editedAt: 200, payload: { archived: true } };
    const day: Operation = { id: 'day', type: 'day.location', entityId: 'day1', syncEpoch: trip.syncEpoch, expectedRevision: 0, editedAt: 300, payload: { location: null } };
    const result = await sync(trip, owner, [edit(trip, 400, 'Dinner'), archive, day, settings, edit(trip, 50, 'Coffee', 'coffee')]);
    expect(result.results.map(r => r.status)).toEqual(Array(5).fill('accepted'));
    expect(result.snapshot?.name).toBe(name + ' edited');
    expect(result.snapshot?.archived).toBe(true);
    expect(result.snapshot?.days[0]?.locationRevision).toBe(1);
    expect(result.snapshot?.expenses).toHaveLength(2);
  });
  it('fills only missing FX without becoming a newer user edit or overwriting a concurrent edit', async () => {
    const owner = await session(), trip = await create(owner);
    const foreign = { ...expense('foreign'), currency: 'JPY' };
    const added = (await sync(trip, owner, [{ ...addExpense(trip, foreign), editedAt: 100 }])).snapshot!.expenses[0]!;
    const conversion = { homeAmountMinor: '5000', rate: '0.005', rateDate: '2026-10-01', kind: 'manual' as const, source: 'Cached test', quoteId: null };
    const fill: Operation = { id: crypto.randomUUID(), syncEpoch: trip.syncEpoch, type: 'expense.upsert', entityId: added.id, payload: { ...added, title: 'Do not replace', conversion }, expectedRevision: added.revision, conversionOnly: true };
    const filled = await sync(trip, owner, [fill]);
    expect(filled.results[0]?.status).toBe('accepted');
    expect(filled.snapshot?.expenses[0]?.title).toBe('Dinner');
    expect(filled.snapshot?.expenses[0]?.conversion?.homeAmountMinor).toBe('5000');
    expect(filled.snapshot?.writeClock).toBe(100);
    await sync(trip, owner, [{ ...addExpense(trip, { ...foreign, title: 'User changed' }), editedAt: 200 }]);
    const stale = await sync(trip, owner, [{ ...fill, id: 'delayed-fill' }]);
    expect(stale.results[0]?.status).toBe('superseded');
    expect(stale.snapshot?.expenses[0]?.title).toBe('User changed');
    expect(stale.snapshot?.expenses[0]?.conversion).toBeNull();
  });
  it('preserves legacy revision checks, access control, recovery and graph validation', async () => {
    const owner = await session(), stranger = await session(), trip = await create(owner);
    await sync(trip, owner, [edit(trip, 100, 'Dinner')]);
    expect((await sync(trip, owner, [addExpense(trip, expense('dinner'))])).results[0]?.code).toBe('REVISION_CONFLICT');
    expect((await sync(trip, owner, [{ ...edit(trip, 200, 'Other'), syncEpoch: 'old' }])).results[0]?.code).toBe('SYNC_EPOCH');
    const invalid = { ...addExpense(trip, { ...expense('dinner'), attachment: { kind: 'day' as const, id: 'missing' } }), editedAt: 300 };
    expect((await sync(trip, owner, [invalid])).results[0]?.code).toBe('ATTACHMENT');
    expect((await sync(trip, owner, [edit(trip, 250, 'Valid')])).results[0]?.status).toBe('accepted');
    expect((await request(`/trips/${trip.id}/sync`, stranger, { cursor: 1, syncEpoch: trip.syncEpoch, operations: [edit(trip, 500, 'Stranger')] })).status).toBe(403);
  });
});
