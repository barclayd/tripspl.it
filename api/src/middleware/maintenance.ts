import { createMiddleware } from 'hono/factory';
import type { HonoEnvironment } from '../types/hono';
import { AppError } from '../utils/errors';

export const maintenance = createMiddleware<HonoEnvironment>(async (c, next) => {
  if (c.env.MAINTENANCE_MODE === '1') {
    throw new AppError(503, 'MAINTENANCE', 'TripSplit is temporarily unavailable for maintenance.', true);
  }
  await next();
});
