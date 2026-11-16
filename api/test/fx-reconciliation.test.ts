import { env } from 'cloudflare:workers';
import { evictDurableObject, runDurableObjectAlarm, runInDurableObject } from 'cloudflare:test';
import { describe, expect, it, vi } from 'vitest';
import type { Expense, Operation, Session, SyncResponse, TripSnapshot } from '../src/types/contract';
import { addExpense, create, expense, request, session } from './fixtures';

const day = '2026-10-05';
function estimated(): Expense {
  return { ...expense(), currency: 'USD', conversion: { homeAmountMinor: '8000', rate: '0.8', rateDate: '2026-10-01', source: 'Cached reference', kind: 'manual', quoteId: null, estimateDate: day } };
}
function quote(rate = '0.85'): Response {
  return new Response(`{"date":"${day}","base":"USD","quote":"GBP","rate":${rate}}`);
}
async function sync(trip: TripSnapshot, owner: Session, operations: Operation[]): Promise<SyncResponse> {
  const response = await request(`/trips/${trip.id}/sync`, owner, { cursor: trip.revision, syncEpoch: trip.syncEpoch, operations });
  expect(response.status).toBe(200); return response.json<SyncResponse>();
}
async function alarm(id: string): Promise<void> {
  const stub = env.TRIPS.getByName(id);
  await runInDurableObject(stub, (_, state) => state.storage.setAlarm(Date.now()));
  await runDurableObjectAlarm(stub);
}
async function jobs(id: string): Promise<number> {
  return runInDurableObject(env.TRIPS.getByName(id), (_, state) => state.storage.sql.exec<{ n: number }>('SELECT count(*) AS n FROM fx_reconciliations').one().n);
}

describe('automatic estimate reconciliation', () => {
  it('saves without provider I/O, reconciles the original save day after eviction, and keeps retries stable', async () => {
    const mock = vi.spyOn(globalThis, 'fetch').mockImplementation(async input => {
      expect(new URL(String(input)).searchParams.get('date')).toBe(day);
      return quote();
    });
    const owner = await session(), trip = await create(owner);
    const operation = { ...addExpense(trip, estimated()), editedAt: 100 };
    const saved = await sync(trip, owner, [operation]);
    expect(saved.results[0]?.status).toBe('accepted');
    expect(saved.snapshot?.expenses[0]?.conversion?.estimateDate).toBe(day);
    expect(mock).not.toHaveBeenCalled();
    expect(await jobs(trip.id)).toBe(1);
    await evictDurableObject(env.TRIPS.getByName(trip.id));
    await alarm(trip.id);
    const refreshed = await sync(trip, owner, []);
    expect(refreshed.snapshot?.expenses[0]?.conversion).toMatchObject({ homeAmountMinor: '8500', kind: 'reference', rateDate: day });
    expect(refreshed.snapshot?.expenses[0]?.conversion?.estimateDate).toBeUndefined();
    expect(refreshed.snapshot?.writeClock).toBe(100);
    expect(await jobs(trip.id)).toBe(0);
    const duplicate = await sync(trip, owner, [operation]);
    expect(duplicate.results[0]?.status).toBe('duplicate');
    expect(duplicate.snapshot?.expenses[0]?.conversion?.homeAmountMinor).toBe('8500');
    await alarm(trip.id);
    expect(mock).toHaveBeenCalledTimes(1);
  });

  it('reconciles on the save when the correct reference is already cached', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => quote());
    expect((await request(`/fx?from=USD&to=GBP&date=${day}`)).status).toBe(200);
    const owner = await session(), trip = await create(owner);
    const saved = await sync(trip, owner, [addExpense(trip, estimated())]);
    expect(saved.snapshot?.expenses[0]?.conversion?.homeAmountMinor).toBe('8500');
    expect(saved.snapshot?.expenses[0]?.conversion?.estimateDate).toBeUndefined();
    expect(await jobs(trip.id)).toBe(0);
  });

  it('keeps the expense usable through provider failure, with durable backoff and eventual reconciliation', async () => {
    const mock = vi.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response('Unavailable', { status: 503 }));
    const owner = await session(), trip = await create(owner);
    await sync(trip, owner, [addExpense(trip, estimated()), addExpense(trip)]);
    await alarm(trip.id);
    const afterFailure = await sync(trip, owner, []);
    expect(afterFailure.snapshot?.expenses).toHaveLength(2);
    expect(afterFailure.snapshot?.expenses.find(e => e.currency === 'USD')?.conversion?.homeAmountMinor).toBe('8000');
    const retry = await runInDurableObject(env.TRIPS.getByName(trip.id), (_, state) => state.storage.sql.exec<{ attempts: number; next_attempt: number }>('SELECT attempts,next_attempt FROM fx_reconciliations').one());
    expect(retry.attempts).toBe(1); expect(retry.next_attempt).toBeGreaterThan(Date.now());
    mock.mockImplementation(async () => quote('0.75'));
    await evictDurableObject(env.TRIPS.getByName(trip.id));
    await runInDurableObject(env.TRIPS.getByName(trip.id), (_, state) => { state.storage.sql.exec('UPDATE fx_reconciliations SET next_attempt=0'); });
    await alarm(trip.id);
    expect((await sync(trip, owner, [])).snapshot?.expenses.find(e => e.currency === 'USD')?.conversion?.homeAmountMinor).toBe('7500');
    expect(await jobs(trip.id)).toBe(0);
  });

  it('never replaces manual charges or settled conversions, even during a concurrent quote fetch', async () => {
    const owner = await session(), trip = await create(owner), record = estimated();
    await sync(trip, owner, [{ ...addExpense(trip, record), editedAt: 100 }]);
    const bank: Expense = { ...record, conversion: { homeAmountMinor: '8123', rate: '0.8', rateDate: day, kind: 'manual', source: 'Actual card charge entered by traveller', quoteId: null } };
    // Interleave the actual save path at the provider await, within one object context.
    // This avoids crossing the test runtime's alarm/RPC callback lifetimes.
    let calls = 0;
    await runInDurableObject(env.TRIPS.getByName(trip.id), async instance => {
      vi.spyOn(globalThis, 'fetch').mockImplementation(async () => {
        calls++;
        const result = await instance.sync(owner.user.id, { cursor: trip.revision, syncEpoch: trip.syncEpoch,
          operations: [{ ...addExpense(trip, bank), editedAt: 200 }] });
        expect(result.results[0]?.status).toBe('accepted');
        return quote();
      });
      await instance.alarm();
    });
    expect((await sync(trip, owner, [])).snapshot?.expenses[0]?.conversion?.homeAmountMinor).toBe('8123');
    expect(await jobs(trip.id)).toBe(0);
    await alarm(trip.id); expect(calls).toBe(1);
  });

  it('cancels work on deletion and creates no job for an invalid or legacy manual write', async () => {
    const owner = await session(), trip = await create(owner), record = estimated();
    const invalid = { ...record, attachment: { kind: 'day' as const, id: 'missing' } };
    expect((await sync(trip, owner, [addExpense(trip, invalid)])).results[0]?.status).toBe('rejected');
    expect(await jobs(trip.id)).toBe(0);
    const saved = await sync(trip, owner, [{ ...addExpense(trip, record), editedAt: 100 }]);
    const deletion: Operation = { id: crypto.randomUUID(), syncEpoch: trip.syncEpoch, type: 'expense.delete', entityId: record.id, expectedRevision: saved.snapshot!.expenses[0]!.revision, editedAt: 200, payload: null };
    await sync(trip, owner, [deletion]);
    expect(await jobs(trip.id)).toBe(0);
    const legacy = estimated(); delete legacy.conversion!.estimateDate;
    await sync(trip, owner, [addExpense(trip, legacy)]);
    expect(await jobs(trip.id)).toBe(0);
  });
});
