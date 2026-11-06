import { describe, expect, it } from 'vitest';
import { expenseSchema } from '../src/schemas/trip';
import type { Operation, SyncResponse, TripSnapshot } from '../src/types/contract';
import { addExpense, create, expense, request, session } from './fixtures';

async function sync(trip: TripSnapshot, owner: Awaited<ReturnType<typeof session>>, operations: Operation[]): Promise<SyncResponse> {
  const response = await request(`/trips/${trip.id}/sync`, owner, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations });
  expect(response.status).toBe(200);
  return response.json<SyncResponse>();
}

describe('multi-day expenses', () => {
  it('syncs one total with selected days, then collapses back to a single day', async () => {
    const owner = await session(), trip = await create(owner);
    const hotel = { ...expense(), title: 'Hotel', category: 'stay' as const, amountMinor: '10001', dayIds: ['day1', 'day2'] };
    const added = await sync(trip, owner, [addExpense(trip, hotel)]);
    expect(added.results[0]?.status).toBe('accepted');
    const fetched = await (await request(`/trips/${trip.id}`, owner)).json<TripSnapshot>();
    expect(fetched.expenses).toHaveLength(1);
    expect(fetched.expenses[0]).toMatchObject({ amountMinor: '10001', dayIds: ['day1', 'day2'] });
    const { dayIds: _days, ...single } = fetched.expenses[0]!;
    const edited = await sync(fetched, owner, [{ ...addExpense(fetched, single), expectedRevision: single.revision }]);
    expect(edited.results[0]?.status).toBe('accepted');
    expect(edited.snapshot?.expenses[0]).not.toHaveProperty('dayIds');
    expect(edited.snapshot?.expenses[0]?.amountMinor).toBe('10001');
  });

  it('rejects duplicate, missing and unrelated selected days', async () => {
    const owner = await session(), trip = await create(owner);
    for (const dayIds of [['day1', 'day1'], ['day1', 'unknown'], ['day2', 'unknown']]) {
      const result = await sync(trip, owner, [addExpense(trip, { ...expense(), dayIds })]);
      expect(result.results[0]?.code).toBe('EXPENSE_DAYS');
    }
    for (const dayIds of [[], ['day1'], null]) {
      expect(expenseSchema.safeParse({ ...expense(), dayIds }).success).toBe(false);
    }
    expect((await request(`/trips/${trip.id}`, owner)).status).toBe(200);
  });

  it('protects every selected day during ordinary itinerary edits', async () => {
    const owner = await session(), trip = await create(owner);
    const added = (await sync(trip, owner, [addExpense(trip, { ...expense(), dayIds: ['day1', 'day2'] })])).snapshot!;
    const { name, startsOn, timeZone, homeCurrency, budgetMinor, stops, legs } = added;
    const result = await sync(added, owner, [{ id: crypto.randomUUID(), syncEpoch: added.syncEpoch,
      type: 'trip.update', entityId: added.id, expectedRevision: added.revision,
      payload: { name, startsOn, timeZone, homeCurrency, budgetMinor, stops, legs,
        days: added.days.map(day => day.id === 'day2' ? { ...day, date: '2026-10-03' } : day) } }]);
    expect(result.results[0]?.code).toBe('REFERENCED_ITINERARY');
  });
});
