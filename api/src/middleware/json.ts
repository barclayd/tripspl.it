import { createMiddleware } from 'hono/factory';
import type { HonoEnvironment } from '../types/hono';
import { readJSON } from '../utils/errors';

export function boundedJSON(maximum = 1_048_576) {
  return createMiddleware<HonoEnvironment>(async (c, next) => {
    // Keep the streaming byte limit, exact media-type policy, and fatal UTF-8
    // decoder before OpenAPIHono's Zod validator touches the body. Hono's public
    // body cache lets both validators share this one bounded parse.
    const value = await readJSON(c.req.raw, maximum);
    c.req.bodyCache.json = Promise.resolve(value);
    // Legacy clients may send arbitrary parameters after application/json.
    // Normalize only the already-checked media type for Hono's stricter gate.
    const headers = new Headers(c.req.raw.headers);
    headers.set('Content-Type', 'application/json');
    c.req.raw = new Request(c.req.raw.url, { method: c.req.method, headers });
    await next();
  });
}
