import { describe, expect, it } from 'vitest';
import type { Expense, Operation, SyncResponse, TripReschedule, TripSnapshot } from '../src/types/contract';
import { addExpense, create, draft, expense, request, session } from './fixtures';

type Owner = Awaited<ReturnType<typeof session>>;

/** Three nights in Tokyo from 1 October, with a flight out and one home. */
function tokyo(): TripSnapshot {
  const trip = draft();
  trip.stops = [{ ...trip.stops[0]!, nights: 3 }];
  trip.days = ['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04'].map((date, index) => ({ id: `day${index + 1}`, date, stopId: 'tokyo' }));
  trip.legs = [
    { id: 'out', kind: 'outbound', date: '2026-10-01', fromStopId: null, toStopId: 'tokyo', dayId: 'day1' },
    { id: 'home', kind: 'return', date: '2026-10-04', fromStopId: 'tokyo', toStopId: null, dayId: 'day4' },
  ];
  return trip;
}
function on(day: string, id = crypto.randomUUID()): Expense { return { ...expense(id), attachment: { kind: 'day', id: day } }; }
function reschedule(trip: TripSnapshot, payload: TripReschedule): Operation {
  return { id: crypto.randomUUID(), syncEpoch: trip.syncEpoch, type: 'trip.reschedule', entityId: trip.id, expectedRevision: trip.revision, payload };
}
async function sync(trip: TripSnapshot, user: Owner, operations: Operation[]): Promise<SyncResponse> {
  const response = await request(`/trips/${trip.id}/sync`, user, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations });
  expect(response.status).toBe(200); return response.json<SyncResponse>();
}
/** One night from 10 November: the first and last days stay, the middle two leave. */
function shortened(trip: TripSnapshot, moves = [{ fromDayId: 'day2', toDayId: 'day1' }, { fromDayId: 'day3', toDayId: 'day1' }]): TripReschedule {
  return {
    startsOn: '2026-11-10', stops: [{ id: 'tokyo', nights: 1 }],
    days: [{ id: 'day1', date: '2026-11-10', stopId: 'tokyo' }, { id: 'day4', date: '2026-11-11', stopId: 'tokyo' }],
    legs: trip.legs.map(leg => leg.kind === 'return' ? { ...leg, date: '2026-11-11' } : { ...leg, date: '2026-11-10' }),
    moves,
  };
}

describe('trip reschedules', () => {
  it('remaps all selected expense days and merges overlapping shares', async () => {
    const owner = await session(), trip = await create(owner, tokyo());
    const hotel = { ...on('day1'), dayIds: ['day1', 'day2', 'day3'], amountMinor: '10001' };
    const added = (await sync(trip, owner, [addExpense(trip, hotel)])).snapshot!;
    const result = await sync(added, owner, [reschedule(added, shortened(added))]);
    expect(result.results[0]?.status).toBe('accepted');
    expect(result.snapshot?.expenses).toHaveLength(1);
    expect(result.snapshot?.expenses[0]).toMatchObject({ amountMinor: '10001', attachment: { kind: 'day', id: 'day1' }, revision: 2 });
    expect(result.snapshot?.expenses[0]).not.toHaveProperty('dayIds');
  });

  it('moves a trip to later, longer dates with its days, legs and their expenses', async () => {
    const owner = await session(), trip = await create(owner, tokyo());
    const dinner = on('day2'), flight: Expense = { ...expense(), attachment: { kind: 'leg', id: 'home' } };
    const added = (await sync(trip, owner, [addExpense(trip, dinner), addExpense(trip, flight)])).snapshot!;
    const later = ['2027-03-05', '2027-03-06', '2027-03-07', '2027-03-08', '2027-03-09', '2027-03-10'];
    const ids = ['day1', 'day2', 'day3', 'extra1', 'extra2', 'day4'];
    const result = await sync(added, owner, [reschedule(added, {
      startsOn: '2027-03-05', stops: [{ id: 'tokyo', nights: 5 }],
      days: ids.map((id, index) => ({ id, date: later[index]!, stopId: 'tokyo' })),
      legs: [{ ...added.legs[0]!, date: '2027-03-05' }, { ...added.legs[1]!, date: '2027-03-10', dayId: 'day4' }],
      moves: [],
    })]);
    expect(result.results[0]?.status).toBe('accepted');
    const snapshot = result.snapshot!;
    expect(snapshot.startsOn).toBe('2027-03-05');
    expect(snapshot.stops[0]).toMatchObject({ id: 'tokyo', nights: 5, place: 'Tokyo' });
    expect(snapshot.days.map(day => day.date)).toEqual(later);
    expect(snapshot.legs.find(leg => leg.id === 'home')?.date).toBe('2027-03-10');
    // Nothing left the trip, so every expense stays where it was, untouched.
    expect(snapshot.expenses.map(e => [e.id, e.attachment.id, e.revision]).sort()).toEqual([[dinner.id, 'day2', 1], [flight.id, 'home', 1]].sort());
  });

  it('moves expenses off the days that leave, including ones the client never saw', async () => {
    const owner = await session(), member = await session(), trip = await create(owner, tokyo());
    const invitation = await (await request(`/trips/${trip.id}/invites`, owner, { travellerId: 'b' })).json<{ id: string; token: string }>();
    expect((await request(`/trips/${trip.id}/invites/${invitation.id}/accept`, member, { token: invitation.token })).status).toBe(200);
    const seen = (await sync(trip, owner, [addExpense(trip, on('day2'))])).snapshot!;
    // The member adds one to day 3 before the owner's reschedule, written against `seen`, arrives.
    const unseen = on('day3');
    expect((await sync(seen, member, [addExpense(seen, unseen)])).results[0]?.status).toBe('accepted');
    const stale = await sync(seen, owner, [reschedule(seen, shortened(seen))]);
    expect(stale.results[0]?.status).toBe('conflict');
    const current = stale.snapshot!;
    const result = await sync(current, owner, [reschedule(current, shortened(current))]);
    expect(result.results[0]?.status).toBe('accepted');
    expect(result.snapshot?.days.map(day => day.id)).toEqual(['day1', 'day4']);
    expect(result.snapshot?.expenses.map(e => e.attachment.id)).toEqual(['day1', 'day1']);
    expect(result.snapshot?.expenses.find(e => e.id === unseen.id)?.revision).toBe(2);
  });

  it('only lets the owner reschedule', async () => {
    const owner = await session(), member = await session(), trip = await create(owner, tokyo());
    const invitation = await (await request(`/trips/${trip.id}/invites`, owner, { travellerId: 'b' })).json<{ id: string; token: string }>();
    await request(`/trips/${trip.id}/invites/${invitation.id}/accept`, member, { token: invitation.token });
    const current = await (await request(`/trips/${trip.id}`, owner)).json<TripSnapshot>();
    const response = await request(`/trips/${trip.id}/sync`, member, { cursor: current.revision, syncEpoch: current.syncEpoch, operations: [reschedule(current, shortened(current))] });
    expect(response.status).toBe(403);
  });

  it('rejects reschedules that change where the trip goes or lose a day’s expenses', async () => {
    const owner = await session(), trip = await create(owner, tokyo());
    const current = (await sync(trip, owner, [addExpense(trip, on('day3'))])).snapshot!;
    const code = async (payload: TripReschedule): Promise<string | null | undefined> => (await sync(current, owner, [reschedule(current, payload)])).results[0]?.code;
    expect(await code(shortened(current, [{ fromDayId: 'day2', toDayId: 'day1' }]))).toBe('DAY_MOVES');
    expect(await code(shortened(current, [{ fromDayId: 'day2', toDayId: 'day1' }, { fromDayId: 'day3', toDayId: 'day2' }]))).toBe('DAY_MOVES');
    expect(await code(shortened(current, [{ fromDayId: 'day2', toDayId: 'day1' }, { fromDayId: 'day3', toDayId: 'day1' }, { fromDayId: 'day1', toDayId: 'day4' }]))).toBe('DAY_MOVES');
    expect(await code({ ...shortened(current), stops: [{ id: 'kyoto', nights: 1 }] })).toBe('RESCHEDULE');
    expect(await code({ ...shortened(current), legs: [current.legs[0]!] })).toBe('RESCHEDULE');
    expect(await code({ ...shortened(current), legs: current.legs.map(leg => ({ ...leg, kind: 'transfer' as const })) })).toBe('RESCHEDULE');
    expect(await code({ ...shortened(current), startsOn: '2026-11-11' })).toBe('DAYS');
    expect(await code({ ...shortened(current), stops: [{ id: 'tokyo', nights: 2 }] })).toBe('DAYS');
    const unchanged = await (await request(`/trips/${trip.id}`, owner)).json<TripSnapshot>();
    expect(unchanged.days).toEqual(current.days); expect(unchanged.expenses[0]?.attachment.id).toBe('day3');
  });
});
