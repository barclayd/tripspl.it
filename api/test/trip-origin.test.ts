import { env } from 'cloudflare:workers';
import { evictDurableObject } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import type { Operation, SyncResponse, TripSettings, TripSnapshot } from '../src/types/contract';
import { create, draft, request, session } from './fixtures';

const london = { place: 'London', countryCode: 'GB', latitude: 51.5072, longitude: -0.1276 };
const dublin = { place: 'Dublin', countryCode: 'IE', latitude: 53.3498, longitude: -6.2603 };

function update(trip: TripSnapshot, changes: Partial<TripSettings> = {}): Operation {
  const { name, startsOn, timeZone, homeCurrency, budgetMinor, stops, days, legs } = trip;
  return { id: crypto.randomUUID(), syncEpoch: trip.syncEpoch, type: 'trip.update', entityId: trip.id, expectedRevision: trip.revision, payload: { name, startsOn, timeZone, homeCurrency, budgetMinor, stops, days, legs, ...changes } };
}
async function sync(trip: TripSnapshot, owner: Awaited<ReturnType<typeof session>>, operations: Operation[]): Promise<SyncResponse> {
  const response = await request(`/trips/${trip.id}/sync`, owner, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations });
  expect(response.status).toBe(200); return response.json<SyncResponse>();
}

describe('trip origins', () => {
  it('persists an origin through creation and eviction, and legacy settings updates keep it', async () => {
    const owner = await session();
    const trip = await create(owner, { ...draft(), origin: london });
    expect(trip.origin).toEqual(london);
    await evictDurableObject(env.TRIPS.getByName(trip.id));
    const fetched = await (await request(`/trips/${trip.id}`, owner)).json<TripSnapshot>();
    expect(fetched.origin).toEqual(london);
    const legacy = update(fetched, { name: 'Renamed by legacy client' });
    expect(legacy.payload).not.toHaveProperty('origin');
    const renamed = await sync(fetched, owner, [legacy]);
    expect(renamed.results[0]?.status).toBe('accepted');
    expect(renamed.snapshot?.name).toBe('Renamed by legacy client');
    expect(renamed.snapshot?.origin).toEqual(london);
    const moved = await sync(renamed.snapshot!, owner, [update(renamed.snapshot!, { origin: dublin })]);
    expect(moved.results[0]?.status).toBe('accepted');
    expect(moved.snapshot?.origin).toEqual(dublin);
  });

  it('lets legacy trips go without an origin and add one later', async () => {
    const owner = await session(), legacy = await create(owner);
    expect(legacy).not.toHaveProperty('origin');
    const added = await sync(legacy, owner, [update(legacy, { origin: london })]);
    expect(added.results[0]?.status).toBe('accepted');
    expect(added.snapshot?.origin).toEqual(london);
  });

  it('rejects null, partial and malformed origins at the API boundary', async () => {
    const owner = await session();
    const invalid = [null, {}, { ...london, place: ' ' }, { ...london, countryCode: 'gb' }, { ...london, latitude: 91 }, { ...london, longitude: -181 }, { ...london, currency: 'GBP' }];
    for (const origin of invalid) {
      const response = await request('/trips', owner, { operationId: crypto.randomUUID(), trip: { ...draft(), origin } });
      expect(response.status, JSON.stringify(origin)).toBe(400);
    }
    const trip = await create(owner), operation = update(trip);
    const nulled = { ...operation, payload: { ...operation.payload, origin: null } };
    expect((await request(`/trips/${trip.id}/sync`, owner, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations: [nulled] })).status).toBe(400);
  });
});
