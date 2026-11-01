import { readD1Migrations } from '@cloudflare/vitest-plugin';

// cf currently rejects the Vite plugin's synthetic local D1 IDs. Use its documented
// local Explorer API; this script refuses remote hosts and never touches cloud data.
const origin = new URL(process.env.LOCAL_WORKER_ORIGIN ?? 'http://localhost:5173');
if (origin.protocol !== 'http:' || !['localhost', '127.0.0.1', '[::1]'].includes(origin.hostname)) throw new Error('Local migrations require an HTTP loopback origin.');
const base = `${origin.origin}/cdn-cgi/local/explorer/api`;
async function api(path, body) {
  const response = await fetch(`${base}${path}`, body ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) } : undefined);
  const value = await response.json();
  if (!response.ok || !value.success || value.result?.some?.(result => result.success === false)) throw new Error('Local D1 operation failed: ' + JSON.stringify(value.errors ?? []));
  return value.result;
}
const databases = await api('/d1/database');
const db = databases.find(database => database.name === 'DB');
if (!db) throw new Error('No DB binding found. Start npm run dev first.');
const path = `/d1/database/${encodeURIComponent(db.uuid)}/raw`;
await api(path, { sql: 'CREATE TABLE IF NOT EXISTS d1_migrations(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL UNIQUE,applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)' });
const existing = await api(path, { sql: 'SELECT name FROM d1_migrations' });
const names = new Set(existing.flatMap(result => result.results.rows.map(row => row[0])));
for (const migration of await readD1Migrations(new URL('../migrations', import.meta.url).pathname)) {
  if (names.has(migration.name)) continue;
  await api(path, { batch: [...migration.queries.map(sql => ({ sql })), { sql: 'INSERT INTO d1_migrations(name) VALUES(?)', params: [migration.name] }] });
  console.log(`Applied ${migration.name} to local DB.`);
}
console.log('Local migrations are current.');
