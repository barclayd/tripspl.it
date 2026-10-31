import { bindings, defineConfig, defineWorker, exports, triggers } from 'cf/config';
import * as entrypoint from './src/index.ts' with { type: 'cf-worker' };

const tripWorker = defineWorker({
  name: 'tripsplit-api', entrypoint, compatibilityDate: '2026-10-30',
  exports: { TripRoom: exports.durableObject({ storage: 'sqlite' }) },
});
export default defineConfig({
  worker: {
    ...tripWorker,
    domains: ['api.tripspl.it'],
    env: {
      DB: bindings.d1({ id: '20112438-d042-4b58-8dc0-5395b5c32aee', name: 'tripsplit-accounts' }),
      TRIPS: bindings.durableObject({ worker: tripWorker, exportName: 'TripRoom' }),
      APPLE_AUDIENCE: bindings.text('it.tripspl.TripSplit' as string),
      APPLE_TEAM_ID: bindings.text('' as string),
      APPLE_KEY_ID: bindings.text('' as string),
      APPLE_PRIVATE_KEY: bindings.secret(),
      SESSION_ENCRYPTION_KEY: bindings.secret(),
      INVITE_ORIGIN: bindings.text('' as string),
      APPLE_APP_ID: bindings.text('' as string),
      // Increment after an operator restores server state. Clients must reconcile first.
      RECOVERY_EPOCH: bindings.text('1' as string),
      MAINTENANCE_MODE: bindings.text('0' as string),
    },
    observability: { enabled: true, logs: { enabled: true, invocationLogs: false }, traces: { enabled: true, headSamplingRate: 0.05 } },
    triggers: [triggers.scheduled({ schedule: '*/5 * * * *' })],
  },
});
