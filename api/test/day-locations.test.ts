import { env } from 'cloudflare:workers';
import { evictDurableObject } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import type { Operation, Session, SyncResponse, TripSnapshot } from '../src/types/contract';
import { addExpense, create, request, session } from './fixtures';

const kamakura = { place: 'Kamakura', countryCode: 'JP', latitude: 35.319, longitude: 139.55 };
const yokohama = { place: 'Yokohama', countryCode: 'JP', latitude: 35.4437, longitude: 139.638 };
function location(trip: TripSnapshot, dayId = 'day1', place: typeof kamakura | null = kamakura): Operation {
  return { id: crypto.randomUUID(), type: 'day.location', entityId: dayId, syncEpoch: trip.syncEpoch,
    expectedRevision: trip.days.find(day => day.id === dayId)?.locationRevision ?? 0, payload: { location: place } };
}
async function sync(trip: TripSnapshot, owner: Session, operations: Operation[]): Promise<SyncResponse> {
  const response = await request(`/trips/${trip.id}/sync`, owner, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations });
  expect(response.status).toBe(200);
  return response.json<SyncResponse>();
}

describe('day locations', () => {
  it('persists a single-day override, safely retries it and explicitly restores the itinerary location', async () => {
    const owner = await session(), original = await create(owner);
    const trip = (await sync(original, owner, [addExpense(original)])).snapshot!;
    const operation = location(trip);
    const changed = (await sync(trip, owner, [operation])).snapshot!;
    expect(changed.days[0]?.location).toEqual(kamakura);
    expect(changed.days[0]?.locationRevision).toBe(1);
    expect(changed.days[1]).toEqual(trip.days[1]);
    expect(changed.stops).toEqual(trip.stops);
    expect(changed.expenses).toEqual(trip.expenses);
    await evictDurableObject(env.TRIPS.getByName(trip.id));
    const fetched = await (await request(`/trips/${trip.id}`, owner)).json<TripSnapshot>();
    expect(fetched.days[0]?.location).toEqual(kamakura);
    expect((await sync(fetched, owner, [operation])).results[0]?.status).toBe('duplicate');
    expect((await sync(fetched, owner, [{ ...operation, payload: { location: yokohama } } as Operation])).results[0]?.code).toBe('OPERATION_REUSED');
    const reset = (await sync(fetched, owner, [location(fetched, 'day1', null)])).snapshot!;
    expect(reset.days[0]).not.toHaveProperty('location');
    expect(reset.days[0]?.locationRevision).toBe(2);
  });

  it('composes independent day edits while detecting two edits to the same day', async () => {
    const owner = await session(), trip = await create(owner);
    const changes = await sync(trip, owner, [location(trip), location(trip, 'day2', yokohama)]);
    expect(changes.results.map(result => result.status)).toEqual(['accepted', 'accepted']);
    const conflicting = await sync(changes.snapshot!, owner, [location(trip, 'day1', yokohama)]);
    expect(conflicting.results[0]?.code).toBe('REVISION_CONFLICT');
    expect(conflicting.snapshot?.days[0]?.location).toEqual(kamakura);
    expect((await sync(changes.snapshot!, owner, [location(trip, 'missing')])).results[0]?.code).toBe('DAY_MISSING');
  });

  it('keeps locations through legacy settings and rescheduling by stable day ID', async () => {
    const owner = await session(), original = await create(owner);
    const trip = (await sync(original, owner, [location(original)])).snapshot!;
    const { name, startsOn, timeZone, homeCurrency, budgetMinor, stops, legs } = trip;
    const days = trip.days.map(({ location: _place, locationRevision: _revision, ...day }) => day);
    const legacy: Operation = { id: crypto.randomUUID(), type: 'trip.update', entityId: trip.id,
      syncEpoch: trip.syncEpoch, expectedRevision: trip.revision,
      payload: { name: name + ' renamed', startsOn, timeZone, homeCurrency, budgetMinor, stops, days, legs } };
    const changed = (await sync(trip, owner, [legacy])).snapshot!;
    expect(changed.days[0]?.location).toEqual(kamakura);
    expect((await sync(changed, owner, [legacy])).results[0]?.status).toBe('duplicate');
    const reschedule: Operation = { id: crypto.randomUUID(), type: 'trip.reschedule', entityId: trip.id,
      syncEpoch: trip.syncEpoch, expectedRevision: changed.revision,
      payload: { startsOn: '2026-11-01', stops: stops.map(({ id, nights }) => ({ id, nights })),
        days: days.map((day, index) => ({ ...day, date: `2026-11-0${index + 1}` })), legs, moves: [] } };
    const moved = (await sync(changed, owner, [reschedule])).snapshot!;
    expect(moved.days[0]?.location).toEqual(kamakura);
    expect(moved.days[0]?.locationRevision).toBe(1);
  });

  it('requires the organiser for edits and does not accept malformed locations', async () => {
    const owner = await session(), member = await session(), trip = await create(owner);
    const invitation = await (await request(`/trips/${trip.id}/invites`, owner, { travellerId: 'b' })).json<{ id: string; token: string }>();
    await request(`/trips/${trip.id}/invites/${invitation.id}/accept`, member, { token: invitation.token });
    expect((await request(`/trips/${trip.id}/sync`, member, { cursor: null, syncEpoch: trip.syncEpoch, operations: [location(trip)] })).status).toBe(403);
    for (const place of [{}, { ...kamakura, place: ' ' }, { ...kamakura, latitude: 91 }, { ...kamakura, countryCode: 'jp' }]) {
      const operation = { ...location(trip), payload: { location: place } };
      expect((await request(`/trips/${trip.id}/sync`, owner, { cursor: null, syncEpoch: trip.syncEpoch, operations: [operation] })).status).toBe(400);
    }
    expect((await request(`/trips/${trip.id}/sync`, owner, { cursor: null, syncEpoch: trip.syncEpoch,
      operations: [{ ...location(trip), payload: {} }] })).status).toBe(400);
  });
});
