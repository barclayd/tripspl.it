import { z } from '@hono/zod-openapi';
import { AppError, assert } from '../utils/errors';
import { currencyDigits, rateFraction } from '../utils/money-values';
import { omitUndefined } from './optional';
import currencyMetadata from '../data/currencies.json';

export const id = z.string().min(1).max(128).regex(/^[A-Za-z0-9_-]+$/).openapi('ID');
export const civil = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => { const d = new Date(`${value}T00:00:00Z`); return Number.isFinite(d.valueOf()) && d.toISOString().slice(0, 10) === value && value >= '1900-01-01' && value <= '2200-12-31'; }).openapi('CivilDate', { format: 'date', description: 'Valid Gregorian civil date from 1900-01-01 through 2200-12-31; no time zone conversion.' });
// Give nullable wrappers their own references: the pinned OpenAPI generator
// otherwise intersects a nonnullable $ref with a nullable type using allOf.
const nullableId = id.nullable().openapi('NullableID');
const nullableCivil = civil.nullable().openapi('NullableCivilDate');
export const amount = z.string().regex(/^(0|[1-9]\d{0,11})$/).openapi('MinorUnits', { description: 'Exact nonnegative integer minor-unit string, at most 999999999999. Never a JSON number.' });
const positiveAmount = amount.refine(v => BigInt(v) > 0n).openapi('PositiveMinorUnits', { pattern: '^[1-9]\\d{0,11}$', description: 'Exact positive integer minor-unit string, from 1 through 999999999999. Zero is only allowed for budgets and converted totals.' });
export const currency = z.string().regex(/^[A-Z]{3}$/).refine(value => { try { currencyDigits(value); return true; } catch { return false; } }).openapi('CurrencyCode', { enum: Object.keys(currencyMetadata.minorUnits).sort(), description: 'Supported ISO 4217 code from the bundled currency metadata.' });
const revision = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
const shortText = z.string().trim().min(1).max(120);
const timeZone = z.string().min(1).max(80).refine(value => {
  // Require a named zone, not the numeric UTC-offset syntax supported by newer Intl runtimes.
  if (!/^[A-Za-z][A-Za-z0-9_+\-/]*$/.test(value)) return false;
  try { new Intl.DateTimeFormat('en', { timeZone: value }); return true; } catch { return false; }
});
const decimalRate = z.string().max(32).refine(value => { try { rateFraction(value); return true; } catch { return false; } }).openapi('DecimalRate', { description: 'Exact positive decimal text with at most 18 significant digits, 18 fractional digits and 12 whole digits. Zero, exponent notation and binary floating-point conversion are forbidden; precision is checked at runtime.' });
export const conversionSchema = z.strictObject({ homeAmountMinor: amount, rate: decimalRate, rateDate: civil, source: z.string().min(1).max(120), kind: z.enum(['reference', 'manual']), quoteId: nullableId }).openapi('Conversion');
const conversion = conversionSchema.nullable().openapi('NullableConversion');
export const travellerSchema = z.strictObject({ id, name: shortText, hue: z.number().min(0).max(360), archived: z.boolean(), revision }).openapi('Traveller');
const countryCode = z.string().regex(/^[A-Z]{2}$/);
const latitude = z.number().min(-90).max(90), longitude = z.number().min(-180).max(180);
export const stopSchema = z.strictObject({ id, countryCode, place: shortText, nights: z.number().int().min(0).max(365), currency, latitude, longitude, timeZone: timeZone.optional() })
  .transform(omitUndefined).openapi('Stop');
export const originSchema = z.strictObject({ place: shortText, countryCode, latitude, longitude }).openapi('TripOrigin', { description: 'Where the trip sets off from and returns to. Optional and never null; a settings update that omits it keeps the saved origin.' });
export const daySchema = z.strictObject({ id, date: civil, stopId: id }).openapi('TripDay');
export const legSchema = z.strictObject({ id, kind: z.enum(['outbound', 'transfer', 'return']), date: civil, fromStopId: nullableId, toStopId: nullableId, dayId: nullableId }).openapi('TravelLeg');
export const categorySchema = z.enum(['food', 'coffee', 'stay', 'activity', 'transport', 'shopping', 'flight', 'train', 'taxi', 'other']).openapi('Category');
export const expenseSchema = z.strictObject({ id, revision, attachment: z.strictObject({ kind: z.enum(['day', 'leg']), id }), title: shortText, category: categorySchema, amountMinor: positiveAmount, currency, status: z.enum(['planned', 'paid']), paidOn: nullableCivil, paidBy: id, splitWith: z.array(id).min(1).max(40), conversion, returnPairId: id.optional().openapi({ description: 'Shared by both halves of a return ticket, one on the outbound leg and one on the return leg, so they edit and delete together. Optional and never null; an upsert that omits it unlinks that half, and a half without its partner is a plain expense.' }) }).openapi('Expense');
export const repaymentSchema = z.strictObject({ id, revision, fromTravellerId: id, toTravellerId: id, amountMinor: positiveAmount, currency, paidOn: civil, conversion, note: z.string().max(500) }).openapi('Repayment');
const settingsFields = z.strictObject({ name: shortText, startsOn: civil, timeZone: z.string().max(100).refine(value => { try { new Intl.DateTimeFormat('en', { timeZone: value }); return true; } catch { return false; } }), homeCurrency: currency, budgetMinor: amount, origin: originSchema.optional(), stops: z.array(stopSchema).min(1).max(30), days: z.array(daySchema).min(1).max(400), legs: z.array(legSchema).max(100) });
export const settingsSchema = settingsFields.openapi('TripSettings');
export const rescheduleSchema = z.strictObject({
  startsOn: civil,
  stops: z.array(z.strictObject({ id, nights: z.number().int().min(0).max(365) }).openapi('StopNights')).min(1).max(30),
  days: z.array(daySchema).min(1).max(400),
  legs: z.array(legSchema).max(100),
  moves: z.array(z.strictObject({ fromDayId: id, toDayId: id }).openapi('DayMove')).max(400),
}).openapi('TripReschedule', { description: 'New dates for a trip: its first day, the nights at each of its stops in order, and the days and legs that follow from them. Legs keep their IDs and only change date and day. Every day that leaves the trip names a kept day in `moves`, which its expenses move to, including ones added elsewhere since.' });
export const snapshotSchema = settingsFields.extend({ id, revision, syncEpoch: z.string().min(1).max(128), ownerTravellerId: id, currentTravellerId: id, role: z.enum(['owner', 'member']), travellers: z.array(travellerSchema).min(1).max(40), expenses: z.array(expenseSchema).max(10000), repayments: z.array(repaymentSchema).max(10000), archived: z.boolean(), updatedAt: z.iso.datetime() }).openapi('TripSnapshot');
const common = { id, syncEpoch: z.string().min(1).max(128), entityId: id };
export const operationSchema = z.discriminatedUnion('type', [
  z.strictObject({ ...common, type: z.literal('expense.upsert'), expectedRevision: revision.nullable(), payload: expenseSchema }).openapi('ExpenseUpsertOperation'),
  z.strictObject({ ...common, type: z.literal('expense.delete'), expectedRevision: revision, payload: z.null() }).openapi('ExpenseDeleteOperation'),
  z.strictObject({ ...common, type: z.literal('repayment.upsert'), expectedRevision: revision.nullable(), payload: repaymentSchema }).openapi('RepaymentUpsertOperation'),
  z.strictObject({ ...common, type: z.literal('repayment.delete'), expectedRevision: revision, payload: z.null() }).openapi('RepaymentDeleteOperation'),
  z.strictObject({ ...common, type: z.literal('traveller.upsert'), expectedRevision: revision.nullable(), payload: travellerSchema }).openapi('TravellerUpsertOperation'),
  z.strictObject({ ...common, type: z.literal('trip.update'), expectedRevision: revision, payload: settingsSchema }).openapi('TripUpdateOperation'),
  z.strictObject({ ...common, type: z.literal('trip.reschedule'), expectedRevision: revision, payload: rescheduleSchema }).openapi('TripRescheduleOperation'),
  z.strictObject({ ...common, type: z.literal('trip.archive'), expectedRevision: revision, payload: z.strictObject({ archived: z.boolean() }) }).openapi('TripArchiveOperation'),
]).openapi('Operation');
export const syncSchema = z.strictObject({ cursor: revision.nullable(), syncEpoch: z.string().max(128).nullable(), operations: z.array(operationSchema).max(50) }).openapi('SyncRequest');
export function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const result = schema.safeParse(value);
  if (!result.success) throw validationError(result.error);
  return result.data;
}
export function validationError(error: z.ZodError): AppError {
  return new AppError(400, 'VALIDATION', 'Invalid request fields: ' + error.issues.slice(0, 4).map(issue => issue.path.join('.')).join(', '));
}
export function validateTrip(trip: z.infer<typeof snapshotSchema>): void {
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
  // Halves of a return ticket are written one operation at a time, so a lone half is valid.
  const legKinds = new Map(trip.legs.map(leg => [leg.id, leg.kind])), pairs = new Map<string, string>();
  for (const e of trip.expenses) {
    assert((e.attachment.kind === 'day' ? days : legs).has(e.attachment.id), 'ATTACHMENT', 'An expense must refer to an existing day or leg.');
    if (e.returnPairId !== undefined) {
      const kind = e.attachment.kind === 'leg' ? legKinds.get(e.attachment.id) : undefined;
      assert((kind === 'outbound' || kind === 'return') && pairs.get(e.returnPairId) !== kind, 'RETURN_PAIR', 'A return ticket has one half on the outbound leg and one on the return leg.');
      pairs.set(e.returnPairId, pairs.has(e.returnPairId) ? 'both' : kind);
    }
    assert(travellers.has(e.paidBy) && e.splitWith.every(id => travellers.has(id)) && new Set(e.splitWith).size === e.splitWith.length, 'TRAVELLER', 'Expense travellers must exist and beneficiaries must be unique.');
    assert(e.status === 'paid' ? e.paidOn !== null : e.paidOn === null, 'PAID_DATE', 'Paid expenses need a paid date; planned expenses have no paid date.');
  }
  for (const r of trip.repayments) assert(travellers.has(r.fromTravellerId) && travellers.has(r.toTravellerId) && r.fromTravellerId !== r.toTravellerId, 'REPAYMENT', 'Repayment requires two different existing travellers.');
}
