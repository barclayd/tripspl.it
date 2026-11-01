import { Hono } from 'hono';
import type { HonoEnvironment } from '../types/hono';
import { assert } from '../utils/errors';
import { jsonHeaders, notFound } from '../utils/http';

export function createPublicRoutes() {
  const app = new Hono<HonoEnvironment>();
  app.get('/.well-known/apple-app-site-association', c => {
    if (c.req.method !== 'GET') notFound();
    assert(/^[A-Z0-9]{10}\.[A-Za-z0-9.-]+$/.test(c.env.APPLE_APP_ID), 'LINKS_NOT_CONFIGURED', 'Universal links are not configured.', 404);
    return c.json({ applinks: { details: [{ appIDs: [c.env.APPLE_APP_ID], components: [{ '/': '/invite/*' }] }] } }, 200, jsonHeaders);
  });
  app.get('/invite/:tripId/:inviteId', c => {
    if (c.req.method !== 'GET' || !/^\/invite\/[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+$/.test(c.req.path)) notFound();
    return new Response('<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1"><title>TripSplit invitation</title><h1>TripSplit invitation</h1><p>Open this invitation on an iPhone with TripSplit installed. Sign in with Apple to join the trip.</p></html>', { headers: { 'Content-Type': 'text/html;charset=utf-8', 'Cache-Control': 'no-store', 'Content-Security-Policy': "default-src 'none'; style-src 'none'; frame-ancestors 'none'", 'Referrer-Policy': 'no-referrer' } });
  });
  return app;
}
