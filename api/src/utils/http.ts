import { AppError } from './errors';

export const jsonHeaders = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };

export function notFound(): never {
  throw new AppError(404, 'NOT_FOUND', 'Endpoint not found.');
}
