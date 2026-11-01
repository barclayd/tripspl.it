import { z } from '@hono/zod-openapi';
import { id } from './trip';

export const emptyBodySchema = z.strictObject({});
export const appleSignInSchema = z.strictObject({
  challengeId: id,
  identityToken: z.string().min(1).max(16384),
  authorizationCode: z.string().min(1).max(4096),
  displayName: z.string().trim().min(1).max(120).optional(),
});
export const refreshTokenSchema = z.strictObject({ refreshToken: z.string().regex(/^[a-f0-9]{64}$/) });
export const userSchema = z.object({ id: z.string(), displayName: z.string() });
export const sessionSchema = z.object({ user: userSchema, accessToken: z.string(), refreshToken: z.string(), expiresAt: z.string() });
export const challengeSchema = z.object({ id: z.string(), nonce: z.string(), expiresAt: z.string() });
