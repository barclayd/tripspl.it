import { OpenAPIHono } from '@hono/zod-openapi';
import { maintenance } from './middleware/maintenance';
import { createPublicRoutes } from './routes/public';
import { createV1Routes } from './routes/v1/api';
import { validationError } from './schemas/trip';
import type { HonoEnvironment } from './types/hono';
import { errorResponse } from './utils/errors';
import { notFound } from './utils/http';

const app = new OpenAPIHono<HonoEnvironment>({
  // Preserve URL.pathname matching instead of decoding path aliases.
  getPath: request => new URL(request.url).pathname,
  defaultHook: result => {
    if (!result.success) throw validationError(result.error);
  },
});

app.onError(errorResponse);
app.notFound(notFound);
app.use('*', async (c, next) => {
  if (c.req.path === '/v1/health' && c.req.method === 'GET') return next();
  return maintenance(c, next);
});
app.route('/', createPublicRoutes());
app.route('/v1', createV1Routes());

export default app;
