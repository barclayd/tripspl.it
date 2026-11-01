import { z } from '@hono/zod-openapi';
import { civil, id, snapshotSchema } from './trip';

export const okSchema = z.object({ ok: z.literal(true) }).openapi('Success');
export const errorSchema = z.object({ error: z.object({ code: z.string(), message: z.string(), retryable: z.boolean() }) }).openapi('APIError');
export const createTripSchema = z.strictObject({ operationId: id, trip: snapshotSchema }).openapi('CreateTripRequest');
export const tripParamsSchema = z.object({ tripId: id });
export const inviteParamsSchema = tripParamsSchema.extend({ inviteId: id });
export const memberParamsSchema = tripParamsSchema.extend({ travellerId: id });
export const inviteSchema = z.strictObject({ travellerId: id }).openapi('CreateInvitationRequest');
export const acceptInviteSchema = z.strictObject({ token: z.string().regex(/^[a-f0-9]{64}$/) }).openapi('AcceptInvitationRequest');
export const nudgeSchema = z.strictObject({ travellerId: id }).openapi('NudgeRequest');
export const nudgeResultSchema = z.object({
  status: z.enum(['sent', 'notJoined']).openapi({ description: '`notJoined` when the traveller has no TripSplit account on this trip, so nobody can be buzzed. It is not recorded.' }),
  nudgedOn: civil,
}).openapi('NudgeResult');
const deviceToken = z.string().regex(/^[a-f0-9]{64,200}$/).openapi({ description: 'Hex APNs device token.' });
export const deviceSchema = z.strictObject({ token: deviceToken, environment: z.enum(['sandbox', 'production']) }).openapi('DeviceRegistration');
export const deviceTokenSchema = z.strictObject({ token: deviceToken }).openapi('DeviceToken');
export const invitationSchema = z.object({ id: z.string(), token: z.string(), expiresAt: z.string(), url: z.string().nullable() }).openapi('Invitation');
export const operationResultSchema = z.object({
  id: z.string(), status: z.enum(['accepted', 'duplicate', 'conflict', 'rejected']),
  revision: z.number().nullable(), code: z.string().nullable(), message: z.string().nullable(),
}).openapi('OperationResult');
export const syncResponseSchema = z.object({
  cursor: z.number(), syncEpoch: z.string(), snapshot: snapshotSchema.nullable().openapi('NullableTripSnapshot'),
  results: z.array(operationResultSchema),
}).openapi('SyncResponse');
export const fxQuoteSchema = z.object({ id: z.string(), from: z.string(), to: z.string(), rate: z.string(), requestedDate: z.string(), rateDate: z.string(), source: z.string() }).openapi('FXQuote');
export const fxTableSchema = z.object({
  base: z.string(), requestedDate: z.string(), rateDate: z.string(), source: z.string(),
  rates: z.record(z.string(), z.string()).openapi({ description: 'Exact decimal rate from the base to each supported currency, including the base itself.' }),
}).openapi('FXTable');
export const tripListSchema = z.object({ trips: z.array(snapshotSchema), nextCursor: z.string().nullable() }).openapi('TripList');
export const deletionPendingSchema = z.object({ status: z.literal('pending') }).openapi('DeletionPending');
export const liveHintSchema = z.object({ type: z.literal('changed'), revision: z.number(), syncEpoch: z.string() }).openapi('LiveHint');

// URLSearchParams.get() used the first occurrence, including an empty value.
const firstQueryValue = z.union([z.string(), z.array(z.string()).min(1)]).transform(value => typeof value === 'string' ? value : value[0]!);
export const tripListQuerySchema = z.object({ cursor: firstQueryValue.optional() });
export const fxQuerySchema = z.object({
  from: firstQueryValue.default('').openapi({ param: { required: true }, description: 'Supported source currency code. The first value is used when repeated.' }),
  to: firstQueryValue.default('').openapi({ param: { required: true }, description: 'Supported target currency code. The first value is used when repeated.' }),
  date: firstQueryValue.default('').openapi({ param: { required: true }, description: 'Requested Gregorian civil date (YYYY-MM-DD). The first value is used when repeated.' }),
});
export const fxTableQuerySchema = z.object({
  base: firstQueryValue.default('').openapi({ param: { required: true }, description: 'Supported base currency code. The first value is used when repeated.' }),
  date: firstQueryValue.default('').openapi({ param: { required: true }, description: 'Requested Gregorian civil date (YYYY-MM-DD). The first value is used when repeated.' }),
});

export function jsonBody<T extends z.ZodType>(schema: T) {
  return { required: true as const, content: { 'application/json': { schema } } };
}
export function jsonResponse<T extends z.ZodType>(schema: T, description: string) {
  return { description, content: { 'application/json': { schema } } };
}
export const errorResponses = { default: jsonResponse(errorSchema, 'TripSplit error with a stable code and retryability.') };
