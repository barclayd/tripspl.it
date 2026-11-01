import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-plugin';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [cloudflareTest(async () => ({
    main: './src/index.ts',
    miniflare: {
      compatibilityDate: '2026-10-30',
      durableObjects: { TRIPS: { className: 'TripRoom', useSQLite: true } },
      d1Databases: ['DB'],
      bindings: {
        TEST_MIGRATIONS: await readD1Migrations('./migrations'),
        APPLE_AUDIENCE: 'it.tripspl.TripSplit', APPLE_TEAM_ID: '', APPLE_KEY_ID: '', APPLE_PRIVATE_KEY: '', APNS_KEY_ID: '',
        SESSION_ENCRYPTION_KEY: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        INVITE_ORIGIN: '', APPLE_APP_ID: '', RECOVERY_EPOCH: '1', MAINTENANCE_MODE: '0',
      },
    },
  }))],
  test: { setupFiles: ['./test/setup.ts'], testTimeout: 15000 },
});
