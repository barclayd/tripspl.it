import { env } from 'cloudflare:workers';
import { describe, expect, it, vi } from 'vitest';
import type { Operation, SyncResponse, TripSnapshot } from '../../contracts/tripsplit-v1';
import currencyMetadata from '../../contracts/currencies.json';
import { currencyDigits } from '../src/money';
import { parse, snapshotSchema, validateTrip } from '../src/validation';
import { addExpense, create, draft, expense, request, session } from './fixtures';

describe('FX provenance, limits and public rate service', () => {
  it('uses every shared ISO minor-unit exponent, rather than display rounding', () => {
    for (const [currency, exponent] of Object.entries(currencyMetadata.minorUnits)) expect(currencyDigits(currency)).toBe(exponent);
    expect(() => currencyDigits('ZZZ')).toThrow();
  });
  it('fetches exact decimal quotes without sign-in, caches them immutably and recomputes submitted totals', async () => {
    const mock = vi.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response('{"date":"2026-10-01","base":"USD","quote":"GBP","rate":0.123456789012345678}', { headers: { 'Content-Type': 'application/json' } }));
    const first = await request('/fx?from=USD&to=GBP&date=2026-10-01'); expect(first.status).toBe(200);
    const quote = await first.json<{ id: string; rate: string }>(); expect(quote.rate).toBe('0.123456789012345678');
    const second = await request('/fx?from=USD&to=GBP&date=2026-10-01'); expect(await second.json()).toMatchObject({ id: quote.id }); expect(mock).toHaveBeenCalledTimes(1);
    const owner = await session(), trip = await create(owner), record = expense();
    record.currency = 'USD'; record.amountMinor = '10000'; record.conversion = { homeAmountMinor: '999999', rate: '99', rateDate: '2026-10-01', source: 'forged', kind: 'reference', quoteId: quote.id };
    const operation = addExpense(trip, record);
    const result = await (await request(`/trips/${trip.id}/sync`, owner, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations: [operation] })).json<SyncResponse>();
    expect(result.snapshot?.expenses[0]?.conversion).toMatchObject({ homeAmountMinor: '1235', rate: quote.rate, source: 'Frankfurter reference' });
    // Receipt recognition cannot depend on quote availability after the original commit.
    await env.DB.prepare('ALTER TABLE fx_quotes RENAME TO unavailable_quotes').run();
    const duplicate = await (await request(`/trips/${trip.id}/sync`, owner, { cursor: 1, syncEpoch: trip.syncEpoch, operations: [operation] })).json<SyncResponse>();
    expect(duplicate.results[0]?.status).toBe('duplicate');
    const fresh = { ...operation, id: crypto.randomUUID(), entityId: crypto.randomUUID() } as Operation;
    const transient = await request(`/trips/${trip.id}/sync`, owner, { cursor: 1, syncEpoch: trip.syncEpoch, operations: [fresh] });
    expect(transient.status).toBe(500); expect(await transient.json()).toMatchObject({ error: { retryable: true } });
    await env.DB.prepare('ALTER TABLE unavailable_quotes RENAME TO fx_quotes').run();
  });
  it('retains unresolved foreign originals and allows explicit card-charge manual amounts', async () => {
    const owner = await session(), trip = await create(owner), unresolved = expense(), manual = expense();
    unresolved.currency = 'USD'; manual.currency = 'USD';
    manual.conversion = { homeAmountMinor: '8100', rate: '0.8', rateDate: '2026-10-01', source: 'Card statement', kind: 'manual', quoteId: null };
    const result = await (await request(`/trips/${trip.id}/sync`, owner, { cursor: 1, syncEpoch: trip.syncEpoch, operations: [addExpense(trip, unresolved), addExpense(trip, manual)] })).json<SyncResponse>();
    expect(result.snapshot?.expenses.find(e => e.id === unresolved.id)?.conversion).toBeNull();
    expect(result.snapshot?.expenses.find(e => e.id === manual.id)?.conversion).toMatchObject({ homeAmountMinor: '8100', source: 'Manual: Card statement' });
  });
  it('enforces bounded operation batches, streamed bodies, positive expenses and record counts', async () => {
    const owner = await session(), trip = await create(owner);
    const accepted = await request(`/trips/${trip.id}/sync`, owner, { cursor: 1, syncEpoch: trip.syncEpoch, operations: Array.from({ length: 50 }, () => addExpense(trip)) });
    expect(accepted.status).toBe(200); expect((await accepted.json<SyncResponse>()).results).toHaveLength(50);
    expect((await request(`/trips/${trip.id}/sync`, owner, { cursor: 1, syncEpoch: trip.syncEpoch, operations: Array.from({ length: 51 }, () => addExpense(trip)) })).status).toBe(400);
    const zero = expense(); zero.amountMinor = '0';
    expect((await request(`/trips/${trip.id}/sync`, owner, { cursor: 1, syncEpoch: trip.syncEpoch, operations: [addExpense(trip, zero)] })).status).toBe(400);
    expect((await request(`/trips/${trip.id}/sync`, owner, { payload: 'x'.repeat(1_048_576) })).status).toBe(413);
    const largest = draft(); largest.expenses = Array.from({ length: 10000 }, (_, i) => expense(`e${i}`));
    expect(parse(snapshotSchema, largest).expenses).toHaveLength(10000); expect(() => validateTrip(largest)).not.toThrow();
    largest.repayments = [{ id: 'extra', revision: 0, fromTravellerId: 'b', toTravellerId: 'a', amountMinor: '1', currency: 'GBP', paidOn: '2026-10-01', conversion: null, note: '' }];
    expect(() => validateTrip(largest)).toThrow('10,000');
  });
  it('paginates one complete snapshot and rejects misassigned stop nights', async () => {
    const user = await session(); await create(user); await create(user);
    const one = await (await request('/trips', user)).json<{ trips: TripSnapshot[]; nextCursor: string }>(); expect(one.trips).toHaveLength(1); expect(one.nextCursor).toBeTruthy();
    const two = await (await request(`/trips?cursor=${one.nextCursor}`, user)).json<{ trips: TripSnapshot[]; nextCursor: string | null }>(); expect(two.trips).toHaveLength(1); expect(two.nextCursor).toBeNull();
    const bad = draft(); bad.stops[0]!.nights = 0; bad.stops.push({ ...bad.stops[0]!, id: 'osaka', place: 'Osaka', nights: 1 });
    expect(() => validateTrip(bad)).toThrow('ordered stop nights');
  });
});
