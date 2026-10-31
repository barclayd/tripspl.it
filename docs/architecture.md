# TripSplit architecture

Agreed with Dan on 31 October 2026. Native SwiftUI for iPhone v2 (Pop) and iPhone Duo; strict TypeScript on Cloudflare Workers; explicit offline synchronisation; Sign in with Apple. Design reference: `/Users/danbarclay/Downloads/design_handoff_tripsplit/`. The HTML is visual reference, not production code or authoritative financial arithmetic.

## Product rules

- Trips have a reporting currency and a whole-trip budget. Expenses have an original amount/currency, payer and a nonempty subset of travellers receiving equal shares. The payer need not be a beneficiary.
- Planned expenses contribute to expected cost, not debt. Paid expenses contribute to actual cost and balances. A repayment reduces debt without increasing spending. Marking planned as paid updates the same expense.
- Store money as integer minor units encoded as decimal strings in JSON. Use currency metadata for precision; don't copy the prototype's zero-decimal currency list. FX rates are positive decimal strings. Round half-up to the reporting currency's minor unit, then distribute split remainders deterministically by sorted traveller ID. Never use floating-point arithmetic for ledger values.
- Missing conversion rates mean an incomplete total, never a zero-cost expense. Keep the original amount, conversion source, effective rate date and whether a rate is a reference estimate or manually entered. Paid conversions stay fixed unless explicitly edited. Card charges can be entered as an explicit reporting-currency amount.
- Label total/person as an average. Calculate the current traveller's share from actual allocations. Preserve pennies in balances; the prototype's half-unit settlement threshold is inappropriate.
- Trip dates are civil `YYYY-MM-DD` dates, not UTC instants. Stops have ordered nights; days include the departure day and final return day (`sum(nights)+1`). Stable IDs attach expenses to days/legs. Changing itinerary dates or stops must not silently move or discard financial records.
- Travellers are trip-local identities and can exist without accounts. Membership links a verified account to an existing traveller through an organiser-issued invite, never by matching a name. Members can edit expenses with history. Owner controls membership, itinerary and budget. Financially referenced travellers are archived rather than erased.
- Repayments record money transferred elsewhere. No payment processing in v1.

## Ownership and storage

The Worker authenticates requests and routes them to one SQLite-backed `TripRoom` Durable Object per trip ID. The TripRoom is authoritative for the trip, membership, invites, financial records, tombstones, monotonic revision, accepted operation receipts and history. Related writes run in one SQLite transaction without external I/O inside it. Membership is checked at every operation/read and before sending live updates.

D1 stores users, Apple identity associations, device sessions, one-use auth challenges, immutable FX quotes and a user-to-trip discovery index. The index is a projection: a persisted TripRoom outbox updates it with retries/alarms and revision-aware upserts. It never grants access. A trip listing resolves authoritative membership before disclosing a trip. Keep sessions hashed; keep secrets in Worker secret bindings. Do not log tokens or private financial payloads.

Suggested TripRoom tables: `trip`, `travellers`, `members`, `stops`, `days`, `legs`, `expenses`, `expense_shares`, `repayments`, `invites`, `operation_receipts`, `changes`, `directory_outbox`. A current JSON snapshot may be stored/derived for transport, but do not replace the whole trip blindly on every edit.

Suggested D1 tables: `users`, `apple_identities`, `auth_challenges`, `sessions`, `user_trips`, `fx_quotes`. User identity is Apple's verified issuer/subject, not email. The server generates its own user ID. Session refresh rotates credentials; logout and account deletion revoke sessions.

## Offline and recovery

The app persists a confirmed snapshot, pending operations and drafts. Persist an edit and its outbox operation together before showing success. An operation ID stays unchanged across retries and device backup restoration. Maintain a device/session identity separately from operation identity.

The server atomically checks operation receipt, current membership, expected entity revision and invariants; commits changes and receipt; increments the trip revision; then notifies connected devices. Reusing an operation ID with different content is rejected. Concurrent independent expense additions compose. Competing edits return a conflict with current state; retain the local draft for resolution. Use desired state (`status = paid`), never a replay-sensitive toggle command.

Transport uses bounded batches and versioned snapshots in v1. A client sends its last acknowledged revision; changed responses include a complete consistent snapshot. This avoids missing deletes and partial graph states. The protocol can add incremental changes later without changing operation identities. WebSocket messages are refresh hints; foreground/reconnect sync is mandatory. If history has been compacted, return a full snapshot. Never infer that an old pending command was rejected just because its receipt was pruned; retain receipts/tombstones for the trip's lifetime or reject stale sync epochs explicitly.

Use SwiftData only for local persistence, explicitly disabling automatic CloudKit sync (`cloudKitDatabase: .none`). Normal device backups may include local data, drafts and pending operations. Exclude disposable caches, not the only copy of user-created data. Restored snapshots are reconciled with Cloudflare before uploading stale edits. Bind restored data to the authenticated account. Session credentials belong in nonsynchronising, device-bound Keychain storage; a replacement device signs in again. Device backup does not guarantee recovery of changes after its last successful snapshot.

Server recovery is separate: document and test D1 Time Travel and Durable Object point-in-time restoration, including resetting sync epochs after a server rollback so old client cursors cannot suppress recovery.

## Authentication and invitations

Local use and onboarding precede sign-in. Creating/syncing a cloud trip or accepting an invite requires Sign in with Apple. The Worker issues a short-lived, one-use nonce challenge, verifies Apple's signed token (issuer, audience, expiry, nonce and key), exchanges the authorisation code as required, and issues device sessions. Identity verification fails closed if Apple configuration is missing. Do not ship a development login endpoint.

Invite links are created by the owner for an existing traveller, have a cryptographically random secret stored hashed, expire and can be revoked. Accept requires authentication and atomically consumes the invite/link membership. Treat links as bearer secrets and omit them from logs. Native universal links use an explicitly configured associated domain and Apple application identifier; no guessed team ID or fake live URL.

## Native presentation

One app state owns the navigation path `Trips -> Trip -> Day`, sheet drafts, onboarding and map state. Layout changes only presentation. Closed uses the current screen; wide pairs its parent with it; tent reflows the current task. Keep stable view identity, native toolbars, tab bars, sheets and accessibility. iOS 26 baseline; gate Duo APIs to their actual SDK availability (27.1 where required). Xcode 27.1 and an iPhone Duo simulator are available locally.

Implement all designed screens: trips/current/upcoming/past, trip overview and balances, day and travel legs, expense editing, quick convert, seven-step onboarding, globe and the boarding-pass component. Pop is the selected direction; Night informs dark mode. Use Reduce Motion equivalents and Dynamic Type. Seed content is opt-in demo/preview data only, not a new user's trips.

## Verification and delivery

Swift and TypeScript share the contract and money examples under `contracts/`. Test rounding, unequal beneficiary sets, repayments, unresolved conversions, authorisation, duplicate/reordered commands, conflicts, offline restart and backup restoration. Run native builds and exercise iPhone/Duo flows with screenshots/video. Keep credentials and generated builds outside git. Commit task changes, push the branch and open a PR; leave merging to Dan.

The frontend agent owns `ios/`; the backend agent owns `backend/`. Root owns `contracts/`, integration, repository docs/CI and delivery. Coordinate contract changes before implementing them. Both build agents use `gpt-6-astra` with `xhigh` reasoning.
