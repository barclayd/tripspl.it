import { env } from 'cloudflare:workers';
import { createExecutionContext, runInDurableObject } from 'cloudflare:test';
import { expect, it } from 'vitest';
import worker from '../src/index';
import { TripRoom } from '../src/durable-objects/trip-room';
import { create, session } from './fixtures';

it('blocks public traffic in maintenance and rebuilds lost D1 targets from authoritative SQLite', async () => {
  const user = await session(), trip = await create(user), stub = env.TRIPS.getByName(trip.id);
  const maintenance = { ...env, MAINTENANCE_MODE: '1', RECOVERY_EPOCH: '2' };
  const blocked = await worker.fetch(new Request('https://api.example.com/v1/me'), maintenance, createExecutionContext());
  expect(blocked.status).toBe(503); expect(await blocked.json()).toMatchObject({ error: { retryable: true, code: 'MAINTENANCE' } });
  expect((await worker.fetch(new Request('https://api.example.com/v1/health'), maintenance, createExecutionContext())).status).toBe(200);
  await env.DB.prepare('DELETE FROM user_trip_targets').run();
  const result = await runInDurableObject(stub, async (_instance, state) => {
    const recovered = new TripRoom(state, maintenance);
    return recovered.repairDirectory();
  });
  expect(result.tripId).toBe(trip.id);
  expect(await env.DB.prepare('SELECT trip_id FROM user_trip_targets WHERE user_id=?').bind(user.user.id).first()).toEqual({ trip_id: trip.id });
  expect(await env.DB.prepare('SELECT recovery_epoch FROM user_trips WHERE user_id=?').bind(user.user.id).first()).toEqual({ recovery_epoch: 2 });
});

it('does not confuse an account missing after D1 rollback with an authorized deletion', async () => {
  const user = await session(), trip = await create(user), stub = env.TRIPS.getByName(trip.id);
  await env.DB.batch([env.DB.prepare('DELETE FROM sessions WHERE user_id=?').bind(user.user.id), env.DB.prepare('DELETE FROM users WHERE id=?').bind(user.user.id)]);
  const maintenance = { ...env, MAINTENANCE_MODE: '1', RECOVERY_EPOCH: '2' };
  const protectedState = await runInDurableObject(stub, async (_instance, state) => {
    const recovered = new TripRoom(state, maintenance);
    await expect(recovered.repairDirectory()).rejects.toMatchObject({ code: 'RECOVERY_ACCOUNT_MISSING' });
    return state.storage.sql.exec<{ purged: number }>('SELECT purged FROM trip').one();
  });
  expect(protectedState.purged).toBe(0);
});
