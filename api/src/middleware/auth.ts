import { createMiddleware } from 'hono/factory';
import { authenticate, rateLimit, requireApple } from '../services/auth';
import type { HonoEnvironment } from '../types/hono';

export const authRateLimit = createMiddleware<HonoEnvironment>(async (c, next) => {
  if (c.req.method === 'POST' && c.req.path.startsWith('/v1/auth/')) {
    await rateLimit(c.env, `auth:${c.req.header('CF-Connecting-IP') ?? 'local'}`, 30);
  }
  await next();
});

export const fxRateLimit = createMiddleware<HonoEnvironment>(async (c, next) => {
  await rateLimit(c.env, `fx:${c.req.header('CF-Connecting-IP') ?? 'local'}`, 30);
  await next();
});

export const authenticateUser = createMiddleware<HonoEnvironment>(async (c, next) => {
  const user = await authenticate(c.req.raw, c.env);
  await rateLimit(c.env, `user:${user.id}`, 240);
  c.set('principal', user);
  await next();
});

// The Apple sign-in service historically checked configuration after reading
// JSON but before validating its fields. Keep that fail-closed error ordering.
export const appleConfigured = createMiddleware<HonoEnvironment>(async (c, next) => {
  requireApple(c.env);
  await next();
});
