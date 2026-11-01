import type { APIError } from '../../../contracts/tripsplit-v1';

export class AppError extends Error {
  constructor(public readonly status: number, public readonly code: string, message: string, public readonly retryable = false) { super(message); }
}
export function assert(condition: unknown, code: string, message: string, status = 400): asserts condition {
  if (!condition) throw new AppError(status, code, message);
}
export function errorResponse(error: unknown): Response {
  const known = error instanceof AppError;
  const body: APIError = { error: { code: known ? error.code : 'INTERNAL_ERROR', message: known ? error.message : 'The service could not complete this request.', retryable: known ? error.retryable : true } };
  if (!known) console.error(JSON.stringify({ event: 'request_failed', kind: error instanceof Error ? error.name : 'unknown' }));
  return Response.json(body, { status: known ? error.status : 500, headers: { 'Cache-Control': 'no-store' } });
}
export async function readJSON(request: Request, maximum = 1_048_576): Promise<unknown> {
  assert(request.headers.get('content-type')?.split(';')[0] === 'application/json', 'CONTENT_TYPE', 'Use application/json.', 415);
  const reader = request.body?.getReader();
  assert(reader, 'INVALID_JSON', 'A JSON body is required.');
  let size = 0;
  const chunks: Uint8Array[] = [];
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maximum) { await reader.cancel(); throw new AppError(413, 'BODY_TOO_LARGE', 'Request body exceeds the limit.'); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes)); }
  catch { throw new AppError(400, 'INVALID_JSON', 'Request body must be valid JSON.'); }
}
