-- APNs device tokens for nudges. A token belongs to whichever account registered it last.
CREATE TABLE device_tokens (token TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), environment TEXT NOT NULL CHECK(environment IN ('sandbox', 'production')), updated_at INTEGER NOT NULL);
CREATE INDEX device_tokens_user ON device_tokens(user_id);
