import assert from 'node:assert/strict';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import examples from '../contracts/fixtures/transport.json';
import type { createOpenAPIContract } from '../src/contracts/openapi';
import { conversionSchema, expenseSchema, legSchema, operationSchema, repaymentSchema, settingsSchema, snapshotSchema, stopSchema } from '../src/schemas/trip';
import type { Operation } from '../src/types/contract';

type Contract = ReturnType<typeof createOpenAPIContract>;

/** Check JSON Schema semantics, not just the presence of nullable metadata. */
export function verifyContract(document: Contract): void {
  const schemas = document.components?.schemas;
  assert(schemas, 'The contract must expose reusable model schemas.');
  assert(document.paths, 'The contract must expose the v1 routes.');
  const ajv = new Ajv2020({ strict: false, allErrors: true });
  addFormats(ajv);
  const schemaId = 'urn:tripsplit:v1';
  ajv.addSchema({ $id: schemaId, $schema: 'https://json-schema.org/draft/2020-12/schema', components: { schemas } });
  // Compile every component so unresolved refs or malformed schemas fail CI.
  const validators = new Map(Object.keys(schemas).map(name => [name, ajv.compile({ $ref: `${schemaId}#/components/schemas/${name}` })]));
  const accepts = (name: string, value: unknown, expected = true) => {
    const validate = validators.get(name);
    assert(validate, `Missing component: ${name}`);
    assert.equal(validate(value), expected, `${name} ${expected ? 'rejected valid' : 'accepted invalid'} transport data: ${JSON.stringify(validate.errors)}`);
  };
  const without = (value: object, field: string) => Object.fromEntries(Object.entries(value).filter(([key]) => key !== field));

  const trip = snapshotSchema.parse(examples.trip);
  const expense = expenseSchema.parse(examples.expense);
  const repayment = repaymentSchema.parse(examples.repayment);
  const conversion = conversionSchema.parse(examples.conversion);
  const leg = legSchema.parse(examples.leg);
  const stop = trip.stops[0]!;
  accepts('TripSnapshot', examples.trip);
  accepts('TripSnapshot', null, false);
  accepts('TripSnapshot', { ...trip, expenses: [expense], repayments: [repayment], legs: [leg] });
  accepts('TripSnapshot', { ...trip, unknown: true }, false);

  accepts('Stop', stop);
  accepts('Stop', { ...stop, timeZone: 'Asia/Tokyo' });
  accepts('Stop', { ...stop, timeZone: null }, false);
  // This assignment also checks exactOptionalPropertyTypes on the inferred
  // output. A timeZone?: string | undefined output would fail TypeScript.
  const omitted: { timeZone?: string } = stopSchema.parse({ ...stop, timeZone: undefined });
  assert.equal(Object.hasOwn(omitted, 'timeZone'), false);
  assert.equal(stopSchema.safeParse({ ...stop, timeZone: null }).success, false);

  accepts('TravelLeg', { ...leg, fromStopId: null, toStopId: null, dayId: null });
  for (const field of ['fromStopId', 'toStopId', 'dayId']) accepts('TravelLeg', without(leg, field), false);
  accepts('Expense', { ...expense, paidOn: null, conversion: null });
  accepts('Expense', { ...expense, conversion });
  for (const field of ['paidOn', 'conversion']) accepts('Expense', without(expense, field), false);
  for (const invalid of ['0', '1000000000000', '1.25', 10000]) {
    accepts('Expense', { ...expense, amountMinor: invalid }, false);
    accepts('Repayment', { ...repayment, amountMinor: invalid }, false);
  }
  accepts('MinorUnits', '0');
  accepts('Conversion', conversion);
  accepts('Conversion', null, false);
  accepts('Conversion', without(conversion, 'quoteId'), false);
  accepts('NullableConversion', null);
  accepts('SyncResponse', { cursor: 1, syncEpoch: 'epoch', snapshot: null, results: [] });
  accepts('SyncResponse', { cursor: 1, syncEpoch: 'epoch', snapshot: trip, results: [] });
  accepts('SyncResponse', { cursor: 1, syncEpoch: 'epoch', results: [] }, false);
  accepts('APIError', { error: { code: 'VALIDATION', message: 'Invalid request fields: amountMinor', retryable: false } });
  accepts('LiveHint', { type: 'changed', revision: 1, syncEpoch: 'epoch' });

  const settings = settingsSchema.parse(Object.fromEntries(Object.entries(trip).filter(([key]) => Object.hasOwn(settingsSchema.shape, key))));
  const common = { id: 'operation-example', syncEpoch: 'epoch', entityId: 'entity-example' };
  const operations: Operation[] = [
    { ...common, type: 'expense.upsert', expectedRevision: null, payload: expense },
    { ...common, type: 'expense.delete', expectedRevision: 1, payload: null },
    { ...common, type: 'repayment.upsert', expectedRevision: null, payload: repayment },
    { ...common, type: 'repayment.delete', expectedRevision: 1, payload: null },
    { ...common, type: 'traveller.upsert', expectedRevision: null, payload: trip.travellers[0]! },
    { ...common, type: 'trip.update', expectedRevision: 1, payload: settings },
    { ...common, type: 'trip.archive', expectedRevision: 1, payload: { archived: true } },
  ];
  for (const operation of operations) {
    operationSchema.parse(operation);
    accepts('Operation', operation);
  }
  accepts('Operation', { ...operations[0], type: 'expense.delete' }, false);
  accepts('Operation', { ...operations[1], expectedRevision: null }, false);
  accepts('SyncRequest', { cursor: null, syncEpoch: null, operations });
  accepts('SyncRequest', { cursor: null, syncEpoch: null, operations: Array.from({ length: 51 }, () => operations[0]) }, false);
  accepts('SyncRequest', { cursor: null, operations }, false);

  // Only explicitly public endpoints omit bearer authentication. A 101
  // response is documented as a WebSocket upgrade, never a JSON response.
  const publicOperations = new Set(['get /v1/health', 'post /v1/auth/apple/challenge', 'post /v1/auth/apple', 'post /v1/auth/refresh', 'get /v1/fx', 'get /v1/fx/rates']);
  let operationCount = 0;
  for (const [path, item] of Object.entries(document.paths)) {
    assert(path.startsWith('/v1/'));
    for (const method of ['get', 'post', 'delete'] as const) {
      const operation = item?.[method];
      if (!operation) continue;
      operationCount += 1;
      assert.equal(Boolean(operation.security?.some(requirement => 'bearerAuth' in requirement)), !publicOperations.has(`${method} ${path}`), `Incorrect authentication contract for ${method} ${path}`);
    }
  }
  assert.equal(operationCount, 22);
  assert.equal(document.paths['/v1/trips/{tripId}/live']?.get?.responses?.['101'] !== undefined, true);
  assert.deepEqual(document.components?.securitySchemes?.['bearerAuth'], {
    type: 'http', scheme: 'bearer', bearerFormat: 'opaque',
    description: 'TripSplit access token in the Authorization header, including WebSocket upgrades. Never put credentials in URLs.',
  });
  for (const path of ['/v1/fx', '/v1/fx/rates']) {
    for (const parameter of document.paths[path]?.get?.parameters ?? []) {
      if ('$ref' in parameter) throw new Error('FX query parameters must be directly inspectable.');
      assert.equal(parameter.required, true, `FX requires ${parameter.name}.`);
    }
  }
}
