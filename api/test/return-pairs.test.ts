import { describe, expect, it } from 'vitest';
import type { Expense, Operation, SyncResponse, TripSnapshot } from '../src/types/contract';
import { addExpense, create, draft, expense, request, session } from './fixtures';

const legs: TripSnapshot['legs'] = [
  { id: 'out', kind: 'outbound', date: '2026-10-01', fromStopId: null, toStopId: 'tokyo', dayId: 'day1' },
  { id: 'home', kind: 'return', date: '2026-10-02', fromStopId: 'tokyo', toStopId: null, dayId: 'day2' },
];
function half(leg: string, pair: string | undefined, amountMinor: string): Expense {
  return { ...expense(), attachment: { kind: 'leg', id: leg }, title: 'Return flight', category: 'flight', amountMinor, ...(pair === undefined ? {} : { returnPairId: pair }) };
}
async function sync(trip: TripSnapshot, owner: Awaited<ReturnType<typeof session>>, operations: Operation[]): Promise<SyncResponse> {
  const response = await request(`/trips/${trip.id}/sync`, owner, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations });
  expect(response.status).toBe(200); return response.json<SyncResponse>();
}

describe('return ticket pairs', () => {
  it('links a half on the way out to a half on the way home, accepting each alone in between', async () => {
    const owner = await session(), trip = await create(owner, { ...draft(), legs });
    const out = half('out', 'ticket', '21001'), back = half('home', 'ticket', '21000');
    const first = await sync(trip, owner, [addExpense(trip, out)]);
    expect(first.results[0]?.status).toBe('accepted');
    const second = await sync(first.snapshot!, owner, [addExpense(first.snapshot!, back)]);
    expect(second.results[0]?.status).toBe('accepted');
    const saved = second.snapshot!.expenses.filter(e => e.returnPairId === 'ticket');
    expect(saved.map(e => e.attachment.id).sort()).toEqual(['home', 'out']);
  });

  it('unlinks a half when a legacy upsert omits the pair', async () => {
    const owner = await session(), trip = await create(owner, { ...draft(), legs });
    const out = half('out', 'ticket', '21001'), back = half('home', 'ticket', '21000');
    const linked = await sync(trip, owner, [addExpense(trip, out), addExpense(trip, back)]);
    expect(linked.results.map(r => r.status)).toEqual(['accepted', 'accepted']);
    const { returnPairId: _pair, ...legacy } = { ...back, revision: 1 };
    const operation: Operation = { id: crypto.randomUUID(), syncEpoch: trip.syncEpoch, type: 'expense.upsert', entityId: back.id, expectedRevision: 1, payload: legacy };
    const edited = await sync(linked.snapshot!, owner, [operation]);
    expect(edited.results[0]?.status).toBe('accepted');
    expect(edited.snapshot!.expenses.find(e => e.id === back.id)).not.toHaveProperty('returnPairId');
    expect(edited.snapshot!.expenses.find(e => e.id === out.id)?.returnPairId).toBe('ticket');
  });

  it('rejects a pair off the travel legs or twice on one leg, and a null pair', async () => {
    const owner = await session(), trip = await create(owner, { ...draft(), legs });
    const onDay = { ...half('out', 'day', '100'), attachment: { kind: 'day' as const, id: 'day1' } };
    const twice = [half('out', 'twice', '100'), half('out', 'twice', '100')];
    const rejected = await sync(trip, owner, [addExpense(trip, onDay), ...twice.map(e => addExpense(trip, e))]);
    expect(rejected.results.map(r => [r.status, r.code])).toEqual([['rejected', 'RETURN_PAIR'], ['accepted', null], ['rejected', 'RETURN_PAIR']]);
    const nulled = { ...addExpense(trip, half('home', undefined, '100')), payload: { ...half('home', undefined, '100'), returnPairId: null } };
    expect((await request(`/trips/${trip.id}/sync`, owner, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations: [nulled] })).status).toBe(400);
  });
});
