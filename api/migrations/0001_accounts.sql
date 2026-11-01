PRAGMA foreign_keys = ON;
CREATE TABLE users (id TEXT PRIMARY KEY, display_name TEXT NOT NULL, created_at TEXT NOT NULL, deleting INTEGER NOT NULL DEFAULT 0);
CREATE TABLE apple_identities (subject TEXT PRIMARY KEY, user_id TEXT NOT NULL UNIQUE REFERENCES users(id), encrypted_grant TEXT);
CREATE TABLE auth_challenges (id TEXT PRIMARY KEY, nonce_hash TEXT NOT NULL, expires_at INTEGER NOT NULL);
CREATE INDEX challenges_expiry ON auth_challenges(expires_at);
CREATE TABLE sessions (id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), access_hash TEXT NOT NULL UNIQUE, refresh_hash TEXT NOT NULL UNIQUE, access_expires_at INTEGER NOT NULL, refresh_expires_at INTEGER NOT NULL);
CREATE INDEX sessions_user ON sessions(user_id);
CREATE TABLE user_trips (user_id TEXT NOT NULL, trip_id TEXT NOT NULL, revision INTEGER NOT NULL, recovery_epoch INTEGER NOT NULL DEFAULT 1, active INTEGER NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(user_id, trip_id));
-- These durable intents make account cleanup independent of the discovery projection.
CREATE TABLE user_trip_targets (user_id TEXT NOT NULL, trip_id TEXT NOT NULL, PRIMARY KEY(user_id, trip_id));
CREATE TABLE deletion_jobs (user_id TEXT PRIMARY KEY, encrypted_grant TEXT, cursor TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, next_attempt_at INTEGER NOT NULL DEFAULT 0);
CREATE TABLE fx_quotes (id TEXT PRIMARY KEY, from_currency TEXT NOT NULL, to_currency TEXT NOT NULL, requested_date TEXT NOT NULL, rate_date TEXT NOT NULL, rate TEXT NOT NULL, source TEXT NOT NULL, UNIQUE(from_currency, to_currency, requested_date));
CREATE TABLE rate_limits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires_at INTEGER NOT NULL);
