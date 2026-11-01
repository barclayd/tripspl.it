import { z } from '@hono/zod-openapi';
import { id, snapshotSchema } from './trip';

export const okSchema = z.object({ ok: z.literal(true) });
export const errorSchema = z.object({ error: z.object({ code: z.string(), message: z.string(), retryable: z.boolean() }) });
export const createTripSchema = z.strictObject({ operationId: id, trip: snapshotSchema });
export const tripParamsSchema = z.object({ tripId: id });
export const inviteParamsSchema = tripParamsSchema.extend({ inviteId: id });
export const memberParamsSchema = tripParamsSchema.extend({ travellerId: id });
export const inviteSchema = z.strictObject({ travellerId: id });
export const acceptInviteSchema = z.strictObject({ token: z.string().regex(/^[a-f0-9]{64}$/) });
export const invitationSchema = z.object({ id: z.string(), token: z.string(), expiresAt: z.string(), url: z.string().nullable() });
export const syncResponseSchema = z.object({
  cursor: z.number(), syncEpoch: z.string(), snapshot: snapshotSchema.nullable(),
  results: z.array(z.object({
    id: z.string(), status: z.enum(['accepted', 'duplicate', 'conflict', 'rejected']),
    revision: z.number().nullable(), code: z.string().nullable(), message: z.string().nullable(),
  })),
});
export const fxQuoteSchema = z.object({ id: z.string(), from: z.string(), to: z.string(), rate: z.string(), requestedDate: z.string(), rateDate: z.string(), source: z.string() });

// URLSearchParams.get() used the first occurrence, including an empty value.
const firstQueryValue = z.union([z.string(), z.array(z.string()).min(1)]).transform(value => typeof value === 'string' ? value : value[0]!);
export const tripListQuerySchema = z.object({ cursor: firstQueryValue.optional() });
export const fxQuerySchema = z.object({ from: firstQueryValue.default(''), to: firstQueryValue.default(''), date: firstQueryValue.default('') });

export function jsonBody<T extends z.ZodType>(schema: T) {
  return { required: true as const, content: { 'application/json': { schema } } };
}
export function jsonResponse<T extends z.ZodType>(schema: T, description: string) {
  return { description, content: { 'application/json': { schema } } };
}
export const errorResponses = { default: jsonResponse(errorSchema, 'TripSplit error with a stable code and retryability.') };
