import { env } from 'cloudflare:workers';
import { evictDurableObject } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import type { Operation, SyncResponse, TripSettings, TripSnapshot } from '../../contracts/tripsplit-v1';
import { addExpense, create, draft, request, session } from './fixtures';
import { snapshotSchema } from '../src/validation';
import timeZones from '../../ios/TripSplit/Domain/Resources/DestinationTimeZones.json';

function update(trip: TripSnapshot, changes: Partial<TripSettings> = {}): Operation {
  const { name, startsOn, timeZone, homeCurrency, budgetMinor, stops, days, legs } = trip;
  return { id: crypto.randomUUID(), syncEpoch: trip.syncEpoch, type: 'trip.update', entityId: trip.id, expectedRevision: trip.revision, payload: { name, startsOn, timeZone, homeCurrency, budgetMinor, stops, days, legs, ...changes } };
}
async function sync(trip: TripSnapshot, owner: Awaited<ReturnType<typeof session>>, operations: Operation[]): Promise<SyncResponse> {
  const response = await request(`/trips/${trip.id}/sync`, owner, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations });
  expect(response.status).toBe(200); return response.json<SyncResponse>();
}

describe('destination-local stop time zones', () => {
  it('accepts every bundled country-zone choice in the Workers runtime', () => {
    const trip = draft();
    for (const timeZone of new Set(timeZones.countries.flatMap(country => country.identifiers))) {
      expect(snapshotSchema.safeParse({ ...trip, stops: trip.stops.map(stop => ({ ...stop, timeZone })) }).success, timeZone).toBe(true);
    }
  });
  it('persists optional stop zones through creation, eviction and legacy settings retries', async () => {
    const owner = await session(), original = draft();
    original.stops[0]!.timeZone = 'Asia/Tokyo';
    const trip = await create(owner, original);
    expect(trip.stops[0]?.timeZone).toBe('Asia/Tokyo');
    const legacyStops = trip.stops.map(({ timeZone: _timeZone, ...stop }) => stop);
    const operation = update(trip, { name: 'Renamed by legacy client', stops: legacyStops });
    const submitted = JSON.stringify(operation);
    const changed = await sync(trip, owner, [operation]);
    expect(changed.results[0]?.status).toBe('accepted');
    expect(changed.snapshot?.stops[0]?.timeZone).toBe('Asia/Tokyo');
    expect(JSON.stringify(operation)).toBe(submitted);
    await evictDurableObject(env.TRIPS.getByName(trip.id));
    const fetched = await (await request(`/trips/${trip.id}`, owner)).json<TripSnapshot>();
    expect(fetched.stops[0]?.timeZone).toBe('Asia/Tokyo');
    const replay = await sync(fetched, owner, [operation]);
    expect(replay.results[0]?.status).toBe('duplicate');
    expect(replay.snapshot?.stops[0]?.timeZone).toBe('Asia/Tokyo');
    if (operation.type !== 'trip.update') throw new Error('Expected settings operation');
    operation.payload.stops[0]!.timeZone = 'Asia/Tokyo';
    expect((await sync(fetched, owner, [operation])).results[0]?.code).toBe('OPERATION_REUSED');
  });

  it('accepts a zone on a legacy stop and an explicit correction without changing financial dates', async () => {
    const owner = await session(), legacy = await create(owner);
    expect(legacy.stops[0]).not.toHaveProperty('timeZone');
    const paid = (await sync(legacy, owner, [addExpense(legacy)])).snapshot!;
    const changed = await sync(paid, owner, [update(paid, { stops: paid.stops.map(stop => ({ ...stop, timeZone: 'Asia/Tokyo' })) })]);
    expect(changed.results[0]?.status).toBe('accepted');
    const current = changed.snapshot!;
    expect(current.expenses[0]?.paidOn).toBe(paid.expenses[0]?.paidOn);
    expect(current.days).toEqual(paid.days);
    const corrected = await sync(current, owner, [update(current, { stops: current.stops.map(stop => ({ ...stop, timeZone: 'Asia/Seoul' })) })]);
    expect(corrected.results[0]?.status).toBe('accepted');
    expect(corrected.snapshot?.stops[0]?.timeZone).toBe('Asia/Seoul');
    const shifted = update(corrected.snapshot!, { startsOn: '2026-10-02', days: current.days.map(day => ({ ...day, date: day.id === 'day1' ? '2026-10-02' : '2026-10-03' })) });
    expect((await sync(corrected.snapshot!, owner, [shifted])).results[0]?.code).toBe('REFERENCED_ITINERARY');
    expect((await sync(corrected.snapshot!, owner, [update(current)])).results[0]?.code).toBe('REVISION_CONFLICT');
  });

  it('rejects null, unknown and numeric-offset stop zones at the API boundary', async () => {
    const owner = await session();
    for (const invalid of [null, '', 'Not/A_Zone', '+03:00', 'Asia/Tokyo '.repeat(10)]) {
      const trip = draft();
      const response = await request('/trips', owner, { operationId: crypto.randomUUID(), trip: { ...trip, stops: trip.stops.map(stop => ({ ...stop, timeZone: invalid })) } });
      expect(response.status).toBe(400);
    }
    const trip = await create(owner), operation = update(trip);
    if (operation.type !== 'trip.update') throw new Error('Expected settings operation');
    const invalid = { ...operation, payload: { ...operation.payload, stops: trip.stops.map(stop => ({ ...stop, timeZone: null })) } };
    expect((await request(`/trips/${trip.id}/sync`, owner, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations: [invalid] })).status).toBe(400);
  });
});
