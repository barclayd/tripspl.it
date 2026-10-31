import { z } from 'zod';
import type { TripSnapshot } from '../../contracts/tripsplit-v1';
import { AppError, assert } from './errors';
import { currencyDigits, rateFraction } from './money';

export const id = z.string().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/);
export const civil = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => { const d = new Date(`${value}T00:00:00Z`); return Number.isFinite(d.valueOf()) && d.toISOString().slice(0, 10) === value && value >= '1900-01-01' && value <= '2200-12-31'; });
const amount = z.string().regex(/^(0|[1-9]\d{0,11})$/);
const currency = z.string().regex(/^[A-Z]{3}$/).refine(value => { try { currencyDigits(value); return true; } catch { return false; } });
const revision = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
const shortText = z.string().trim().min(1).max(120);
const conversion = z.strictObject({ homeAmountMinor: amount, rate: z.string().max(32).refine(value => { try { rateFraction(value); return true; } catch { return false; } }), rateDate: civil, source: z.string().min(1).max(120), kind: z.enum(['reference', 'manual']), quoteId: id.nullable() }).nullable();
export const travellerSchema = z.strictObject({ id, name: shortText, hue: z.number().min(0).max(360), archived: z.boolean(), revision });
const stop = z.strictObject({ id, countryCode: z.string().regex(/^[A-Z]{2}$/), place: shortText, nights: z.number().int().min(0).max(365), currency, latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) });
const day = z.strictObject({ id, date: civil, stopId: id });
const leg = z.strictObject({ id, kind: z.enum(['outbound', 'transfer', 'return']), date: civil, fromStopId: id.nullable(), toStopId: id.nullable(), dayId: id.nullable() });
export const expenseSchema = z.strictObject({ id, revision, attachment: z.strictObject({ kind: z.enum(['day', 'leg']), id }), title: shortText, category: z.enum(['food', 'coffee', 'stay', 'activity', 'transport', 'shopping', 'flight', 'train', 'taxi', 'other']), amountMinor: amount.refine(v => BigInt(v) > 0n), currency, status: z.enum(['planned', 'paid']), paidOn: civil.nullable(), paidBy: id, splitWith: z.array(id).min(1).max(40), conversion });
export const repaymentSchema = z.strictObject({ id, revision, fromTravellerId: id, toTravellerId: id, amountMinor: amount.refine(v => BigInt(v) > 0n), currency, paidOn: civil, conversion, note: z.string().max(500) });
export const settingsSchema = z.strictObject({ name: shortText, startsOn: civil, timeZone: z.string().max(100).refine(value => { try { new Intl.DateTimeFormat('en', { timeZone: value }); return true; } catch { return false; } }), homeCurrency: currency, budgetMinor: amount, stops: z.array(stop).min(1).max(30), days: z.array(day).min(1).max(400), legs: z.array(leg).max(100) });
export const snapshotSchema = settingsSchema.extend({ id, revision, syncEpoch: z.string().min(1).max(128), ownerTravellerId: id, currentTravellerId: id, role: z.enum(['owner', 'member']), travellers: z.array(travellerSchema).min(1).max(40), expenses: z.array(expenseSchema).max(10000), repayments: z.array(repaymentSchema).max(10000), archived: z.boolean(), updatedAt: z.iso.datetime() });
const common = { id, syncEpoch: z.string().min(1).max(128), entityId: id };
export const operationSchema = z.discriminatedUnion('type', [
  z.strictObject({ ...common, type: z.literal('expense.upsert'), expectedRevision: revision.nullable(), payload: expenseSchema }),
  z.strictObject({ ...common, type: z.literal('expense.delete'), expectedRevision: revision, payload: z.null() }),
  z.strictObject({ ...common, type: z.literal('repayment.upsert'), expectedRevision: revision.nullable(), payload: repaymentSchema }),
  z.strictObject({ ...common, type: z.literal('repayment.delete'), expectedRevision: revision, payload: z.null() }),
  z.strictObject({ ...common, type: z.literal('traveller.upsert'), expectedRevision: revision.nullable(), payload: travellerSchema }),
  z.strictObject({ ...common, type: z.literal('trip.update'), expectedRevision: revision, payload: settingsSchema }),
  z.strictObject({ ...common, type: z.literal('trip.archive'), expectedRevision: revision, payload: z.strictObject({ archived: z.boolean() }) }),
]);
export const syncSchema = z.strictObject({ cursor: revision.nullable(), syncEpoch: z.string().max(128).nullable(), operations: z.array(operationSchema).max(50) });
export function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const result = schema.safeParse(value);
  if (!result.success) throw new AppError(400, 'VALIDATION', 'Invalid request fields: ' + result.error.issues.slice(0, 4).map(issue => issue.path.join('.')).join(', '));
  return result.data;
}
export function validateTrip(trip: TripSnapshot): void {
  const unique = (items: { id: string }[]): Set<string> => { const ids = new Set(items.map(item => item.id)); assert(ids.size === items.length, 'DUPLICATE_ID', 'Entity IDs must be unique.'); return ids; };
  const travellers = unique(trip.travellers), stops = unique(trip.stops), days = unique(trip.days), legs = unique(trip.legs);
  unique(trip.expenses); unique(trip.repayments);
  assert(trip.expenses.length + trip.repayments.length <= 10_000, 'RECORD_LIMIT', 'A trip can have at most 10,000 financial records.');
  assert(travellers.has(trip.ownerTravellerId), 'OWNER', 'The owner must be a traveller.');
  assert(!trip.travellers.find(t => t.id === trip.ownerTravellerId)?.archived, 'OWNER', 'The owner cannot be archived.');
  assert(trip.days.length === trip.stops.reduce((sum, s) => sum + s.nights, 0) + 1, 'DAYS', 'Days must include every night and the return day.');
  for (let i = 0; i < trip.days.length; i++) {
    const day = trip.days[i]!;
    const expected = new Date(`${trip.startsOn}T00:00:00Z`); expected.setUTCDate(expected.getUTCDate() + i);
    let remaining = i;
    let expectedStop = trip.stops.at(-1)!;
    for (const stop of trip.stops) {
      if (remaining < stop.nights) { expectedStop = stop; break; }
      remaining -= stop.nights;
    }
    assert(day.date === expected.toISOString().slice(0, 10) && stops.has(day.stopId) && day.stopId === expectedStop.id, 'DAYS', 'Days must follow the trip dates and ordered stop nights, including the return day.');
  }
  for (const leg of trip.legs) assert((leg.fromStopId === null || stops.has(leg.fromStopId)) && (leg.toStopId === null || stops.has(leg.toStopId)) && (leg.dayId === null || days.has(leg.dayId)), 'LEG', 'Travel leg references are invalid.');
  for (const e of trip.expenses) {
    assert((e.attachment.kind === 'day' ? days : legs).has(e.attachment.id), 'ATTACHMENT', 'An expense must refer to an existing day or leg.');
    assert(travellers.has(e.paidBy) && e.splitWith.every(id => travellers.has(id)) && new Set(e.splitWith).size === e.splitWith.length, 'TRAVELLER', 'Expense travellers must exist and beneficiaries must be unique.');
    assert(e.status === 'paid' ? e.paidOn !== null : e.paidOn === null, 'PAID_DATE', 'Paid expenses need a paid date; planned expenses have no paid date.');
  }
  for (const r of trip.repayments) assert(travellers.has(r.fromTravellerId) && travellers.has(r.toTravellerId) && r.fromTravellerId !== r.toTravellerId, 'REPAYMENT', 'Repayment requires two different existing travellers.');
}
