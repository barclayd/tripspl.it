import { createRoute } from '@hono/zod-openapi';
import { appleConfigured, fxRateLimit } from '../../middleware/auth';
import { boundedJSON } from '../../middleware/json';
import { appleSignInSchema, challengeSchema, emptyBodySchema, refreshTokenSchema, sessionSchema, userSchema } from '../../schemas/auth';
import { acceptInviteSchema, createTripSchema, deletionPendingSchema, errorResponses, fxQuerySchema, fxQuoteSchema, fxTableQuerySchema, fxTableSchema, invitationSchema, inviteParamsSchema, inviteSchema, jsonBody, jsonResponse, memberParamsSchema, okSchema, syncResponseSchema, tripListQuerySchema, tripListSchema, tripParamsSchema } from '../../schemas/http';
import { snapshotSchema, syncSchema } from '../../schemas/trip';

const security = [{ bearerAuth: [] }];

export const routes = {
  health: createRoute({ method: 'get', path: '/health', responses: { 200: jsonResponse(okSchema, 'Service health.'), ...errorResponses } }),
  auth: {
    challenge: createRoute({ method: 'post', path: '/auth/apple/challenge', middleware: [boundedJSON(1024)], request: { body: jsonBody(emptyBodySchema) }, responses: { 200: jsonResponse(challengeSchema, 'One-use Apple sign-in challenge.'), ...errorResponses } }),
    apple: createRoute({ method: 'post', path: '/auth/apple', middleware: [boundedJSON(32768), appleConfigured], request: { body: jsonBody(appleSignInSchema) }, responses: { 200: jsonResponse(sessionSchema, 'Authenticated TripSplit session.'), ...errorResponses } }),
    refresh: createRoute({ method: 'post', path: '/auth/refresh', middleware: [boundedJSON(1024)], request: { body: jsonBody(refreshTokenSchema) }, responses: { 200: jsonResponse(sessionSchema, 'Rotated access and refresh credentials.'), ...errorResponses } }),
    logout: createRoute({ method: 'post', path: '/auth/logout', security, middleware: [boundedJSON(1024)], request: { body: jsonBody(refreshTokenSchema) }, responses: { 200: jsonResponse(okSchema, 'Session revoked.'), ...errorResponses } }),
  },
  fx: createRoute({ method: 'get', path: '/fx', middleware: [fxRateLimit], request: { query: fxQuerySchema }, responses: { 200: jsonResponse(fxQuoteSchema, 'Immutable reference quote with exact decimal rate.'), ...errorResponses } }),
  fxRates: createRoute({ method: 'get', path: '/fx/rates', middleware: [fxRateLimit], request: { query: fxTableQuerySchema }, responses: { 200: jsonResponse(fxTableSchema, 'Indicative reference rates from one base, for display-only conversions between any pair.'), ...errorResponses } }),
  me: {
    get: createRoute({ method: 'get', path: '/me', security, responses: { 200: jsonResponse(userSchema, 'Current account.'), ...errorResponses } }),
    delete: createRoute({ method: 'delete', path: '/me', security, middleware: [boundedJSON(1024)], request: { body: jsonBody(emptyBodySchema) }, responses: { 202: jsonResponse(deletionPendingSchema, 'Durable account deletion queued.'), ...errorResponses } }),
  },
  trips: {
    list: createRoute({ method: 'get', path: '/trips', security, request: { query: tripListQuerySchema }, responses: { 200: jsonResponse(tripListSchema, 'One full snapshot per discovery page.'), ...errorResponses } }),
    create: createRoute({ method: 'post', path: '/trips', security, middleware: [boundedJSON()], request: { body: jsonBody(createTripSchema) }, responses: { 201: jsonResponse(snapshotSchema, 'Created trip snapshot.'), ...errorResponses } }),
    get: createRoute({ method: 'get', path: '/trips/{tripId}', security, request: { params: tripParamsSchema }, responses: { 200: jsonResponse(snapshotSchema, 'Authoritative trip snapshot.'), ...errorResponses } }),
    delete: createRoute({ method: 'delete', path: '/trips/{tripId}', security, request: { params: tripParamsSchema }, responses: { 200: jsonResponse(okSchema, 'Trip deleted for every traveller. Owner only; repeating it succeeds, and members then get TRIP_NOT_FOUND.'), ...errorResponses } }),
    sync: createRoute({ method: 'post', path: '/trips/{tripId}/sync', security, middleware: [boundedJSON()], request: { params: tripParamsSchema, body: jsonBody(syncSchema) }, responses: { 200: jsonResponse(syncResponseSchema, 'Ordered operation receipts and optional snapshot.'), ...errorResponses } }),
    live: createRoute({ method: 'get', path: '/trips/{tripId}/live', security, request: { params: tripParamsSchema }, responses: { 101: { description: 'WebSocket upgrade; subsequent messages follow the LiveHint schema and are synchronization hints. Always sync on foreground or reconnect.' }, ...errorResponses } }),
    invite: createRoute({ method: 'post', path: '/trips/{tripId}/invites', security, middleware: [boundedJSON(1024)], request: { params: tripParamsSchema, body: jsonBody(inviteSchema) }, responses: { 200: jsonResponse(invitationSchema, 'One-recipient invitation.'), ...errorResponses } }),
    accept: createRoute({ method: 'post', path: '/trips/{tripId}/invites/{inviteId}/accept', security, middleware: [boundedJSON(1024)], request: { params: inviteParamsSchema, body: jsonBody(acceptInviteSchema) }, responses: { 200: jsonResponse(snapshotSchema, 'Joined trip snapshot.'), ...errorResponses } }),
    revokeInvite: createRoute({ method: 'delete', path: '/trips/{tripId}/invites/{inviteId}', security, request: { params: inviteParamsSchema }, responses: { 200: jsonResponse(okSchema, 'Invitation revoked.'), ...errorResponses } }),
    removeMember: createRoute({ method: 'delete', path: '/trips/{tripId}/members/{travellerId}', security, request: { params: memberParamsSchema }, responses: { 200: jsonResponse(okSchema, 'Membership removed.'), ...errorResponses } }),
  },
};
