import type { CreateTripRequest, Invitation, Success, SyncResponse, TripList, TripSnapshot } from '../types/contract';
import type { Nudge, RoomAction } from '../durable-objects/trip-room';
import { id, parse } from '../schemas/trip';
import { AppError } from '../utils/errors';
import { registerTarget, type Principal } from './auth';

type ActionValue<A extends RoomAction> =
  A['type'] extends 'read' | 'create' | 'accept' ? TripSnapshot :
  A['type'] extends 'sync' ? SyncResponse :
  A['type'] extends 'invite' ? Invitation :
  A['type'] extends 'nudge' ? Nudge :
  Success;

export async function executeRoom<A extends RoomAction>(env: Env, user: Principal, tripId: string, action: A): Promise<ActionValue<A>> {
  const result = await env.TRIPS.getByName(tripId).execute(user, action);
  if (!result.ok) throw new AppError(result.error.status, result.error.code, result.error.message, result.error.retryable);
  // TripRoom.execute's discriminated action dispatch determines the result.
  // Keep that RPC wire union intact and expose its action-specific type here.
  return result.value as ActionValue<A>;
}

export async function createTrip(env: Env, user: Principal, input: CreateTripRequest): Promise<TripSnapshot> {
  await registerTarget(env, user.id, input.trip.id);
  return executeRoom(env, user, input.trip.id, { type: 'create', operationId: input.operationId, trip: input.trip });
}

export async function listTrips(env: Env, user: Principal, cursor?: string): Promise<TripList> {
  if (cursor !== undefined) parse(id, cursor);
  // Targets include acknowledged creates/joins even while the discovery outbox is retrying.
  const candidates = await env.DB.prepare('SELECT trip_id FROM user_trip_targets WHERE user_id=? AND trip_id>? ORDER BY trip_id LIMIT 2').bind(user.id, cursor ?? '').all<{ trip_id: string }>();
  const page = candidates.results.slice(0, 1), trips: TripSnapshot[] = [];
  for (const candidate of page) {
    const result = await env.TRIPS.getByName(candidate.trip_id).execute(user, { type: 'read' });
    if (result.ok) trips.push(result.value as TripSnapshot);
    // A deleted trip gives its slot back, even when the delete's own cleanup didn't land.
    else if (result.error.code === 'TRIP_NOT_FOUND') await env.DB.prepare('DELETE FROM user_trip_targets WHERE user_id=? AND trip_id=?').bind(user.id, candidate.trip_id).run();
    else if (result.error.status !== 403 && result.error.status !== 404) throw new AppError(result.error.status, result.error.code, result.error.message, result.error.retryable);
  }
  return { trips, nextCursor: candidates.results.length > 1 ? page.at(-1)!.trip_id : null };
}
