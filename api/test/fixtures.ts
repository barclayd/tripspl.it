import { env, exports } from 'cloudflare:workers';
import type { Expense, Operation, Session, TripSnapshot } from '../../contracts/tripsplit-v1';
import { issueSession } from '../src/services/auth';

export function draft(id = crypto.randomUUID()): TripSnapshot {
  return {
    id, revision: 0, syncEpoch: 'local', name: 'Japan', startsOn: '2026-10-01', timeZone: 'Asia/Tokyo', homeCurrency: 'GBP', budgetMinor: '200000', ownerTravellerId: 'a', currentTravellerId: 'a', role: 'owner', archived: false, updatedAt: '2026-10-01T00:00:00.000Z',
    travellers: ['a', 'b', 'c'].map((id, index) => ({ id, name: ['Alice', 'Bob', 'Charlie'][index]!, hue: index * 100, archived: false, revision: 0 })),
    stops: [{ id: 'tokyo', countryCode: 'JP', place: 'Tokyo', nights: 1, currency: 'JPY', latitude: 35.68, longitude: 139.69 }],
    days: [{ id: 'day1', date: '2026-10-01', stopId: 'tokyo' }, { id: 'day2', date: '2026-10-02', stopId: 'tokyo' }], legs: [], expenses: [], repayments: [],
  };
}
export function expense(id = crypto.randomUUID()): Expense { return { id, revision: 0, attachment: { kind: 'day', id: 'day1' }, title: 'Dinner', category: 'food', amountMinor: '10000', currency: 'GBP', status: 'paid', paidOn: '2026-10-01', paidBy: 'a', splitWith: ['c', 'a', 'b'], conversion: null }; }
export function addExpense(trip: TripSnapshot, record = expense()): Operation { return { id: crypto.randomUUID(), syncEpoch: trip.syncEpoch, type: 'expense.upsert', entityId: record.id, expectedRevision: null, payload: record }; }
export async function session(name = 'Traveller'): Promise<Session> {
  const user = { id: crypto.randomUUID(), displayName: name };
  await env.DB.prepare('INSERT INTO users(id,display_name,created_at) VALUES(?,?,?)').bind(user.id, name, new Date().toISOString()).run();
  return issueSession(env, user);
}
export function request(path: string, session?: Session, body?: unknown, method = body === undefined ? 'GET' : 'POST'): Promise<Response> {
  return exports.default.fetch(`https://api.example.com/v1${path}`, { method, headers: { ...(session ? { authorization: `Bearer ${session.accessToken}` } : {}), ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
}
export async function create(owner: Session, trip = draft()): Promise<TripSnapshot> {
  const response = await request('/trips', owner, { operationId: crypto.randomUUID(), trip });
  if (response.status !== 201) throw new Error(await response.text());
  return response.json<TripSnapshot>();
}
