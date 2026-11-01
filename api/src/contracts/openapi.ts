import app from '../app';

/** Generate from the same route registry and schemas used to serve requests. */
export function createOpenAPIContract() {
  return app.getOpenAPI31Document({
    openapi: '3.1.0',
    info: {
      title: 'TripSplit API',
      version: '1.0.0',
      description: 'Generated v1 JSON transport contract. Money and rates are exact decimal strings. Runtime refinements, authorization, transactional sync rules and WebSocket semantics are specified in api/docs/protocol.md. Public HTML invitation and Apple association documents are outside this JSON API description.',
    },
    servers: [{ url: 'https://api.tripspl.it' }],
  });
}

// Sort object keys, preserving array order (including discriminated variants).
// No timestamps or host-dependent metadata enter the committed artifact.
function sorted(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sorted);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([key, field]) => [key, sorted(field)]));
  }
  return value;
}

export function serializeOpenAPIContract(): string {
  return JSON.stringify(sorted(createOpenAPIContract()), null, 2) + '\n';
}
