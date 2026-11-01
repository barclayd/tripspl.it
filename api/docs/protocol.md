# HTTP contract v1

JSON over HTTPS under `/v1`. Bearer access token required except challenge, Apple sign-in, refresh, health, exchange-rate lookup and public invite landing/association files. Error shape is `APIError`. IDs are opaque strings (client-created record/operation IDs use UUIDs). Timestamps are ISO 8601 UTC; civil dates use `YYYY-MM-DD`. Field shapes and scalar schemas come from [`../src/schemas/`](../src/schemas/), with the generated portable contract at [`../contracts/openapi.json`](../contracts/openapi.json). All lists, body sizes and batches are bounded. No credentials in query strings or logs.

| Method | Path | Request | Success response |
| --- | --- | --- | --- |
| GET | `/health` | — | `{ok:true}` |
| POST | `/auth/apple/challenge` | `{}` | `AuthChallenge` |
| POST | `/auth/apple` | `{challengeId, identityToken, authorizationCode, displayName?}` | `Session` |
| POST | `/auth/refresh` | `{refreshToken}` | `Session` |
| POST | `/auth/logout` | `{refreshToken}` | `{ok:true}` |
| GET | `/me` | — | `User` |
| DELETE | `/me` | `{}` | 202 `{status:'pending'}` |
| GET | `/trips` | optional `cursor` | `{trips:TripSnapshot[], nextCursor:string|null}` |
| POST | `/trips` | `{operationId, trip:TripSnapshot}` | `TripSnapshot` |
| GET | `/trips/:tripId` | — | `TripSnapshot` |
| POST | `/trips/:tripId/sync` | `SyncRequest` | `SyncResponse` |
| POST | `/trips/:tripId/invites` | `{travellerId}` | `{id, token, expiresAt, url:string|null}` |
| POST | `/trips/:tripId/invites/:inviteId/accept` | `{token}` | `TripSnapshot` |
| DELETE | `/trips/:tripId/invites/:inviteId` | — | `{ok:true}` |
| DELETE | `/trips/:tripId/members/:travellerId` | — | `{ok:true}` |
| GET | `/fx` | `from`, `to`, `date` query parameters | `FXQuote` |
| GET | `/fx/rates` | `base`, `date` query parameters | `FXTable` |
| GET | `/trips/:tripId/live` | WebSocket upgrade (authenticated) | `{type:'changed', revision, syncEpoch}` messages |

Apple challenge `nonce` is a random raw nonce. The app sends its SHA-256 hex digest to Apple's native request. The server checks that digest against Apple's token and consumes the matching challenge exactly once. Verify cryptographic signatures through a maintained library and Apple's keys; require configured bundle audience. Account deletion persists a cleanup job, invalidates app sessions and revokes the stored Apple grant, retrying temporary provider failures. It does not require a fresh Apple sign-in. Shared-trip records remain with account links removed and the linked traveller anonymised; ownership passes to the earliest remaining active member. Trips with no other linked member are removed. These consequences must be disclosed in the native confirmation.

Trip creation is idempotent on operation ID and trip ID, assigns the authenticated user to `ownerTravellerId`, and rejects impersonation. Ignore client-provided role/currentTravellerId as authority. `revision = 0` and `syncEpoch = 'local'` are permitted only in local draft creation; the server returns its own initial revision/epoch. Create must resolve the same original operation after uncertain acknowledgement.

`Stop.timeZone` is an optional named IANA time-zone identifier, such as `Asia/Tokyo`, and is never JSON null. It records the destination-local zone independently of the trip's legacy `timeZone`. Clients use an exact catalogue/Maps zone where available and allow correction of country representative defaults. Existing civil dates are not reinterpreted when a zone changes. During `trip.update`, an omitted stop zone preserves the server's existing zone for that same stable stop ID; a supplied valid zone replaces it. New stops and legacy trips may omit the field. Omitting the field cannot clear a stored value. Operation receipts retain the original submitted payload, including omissions, so legacy retries remain idempotent. Existing revision checks, owner permissions, day ordering and protections for attached financial records still apply.

For new entities `expectedRevision = null`; for edits it is the current confirmed entity revision. The server increments entity revisions; client payload revisions are never trusted. Trip settings use the confirmed trip revision. Financial operations can be sent independently even if unrelated expenses changed the trip revision. A stale sync epoch requires snapshot reconciliation; do not apply commands against an unknown epoch.

Sync requests process operations in order with an atomic transaction per operation. Conflicts/rejections are structured results, not silent drops. Include a snapshot if the cursor/epoch differs or there are results. Keep a rejected local draft visible. Revoked membership returns 403 and closes live subscriptions. Network errors and 5xx are retryable; never auto-retry a 409 conflict with a new revision.

The home-currency equivalent of same-currency expenses is `amountMinor`, regardless of conversion. For foreign-currency reference conversions, validate/recompute against an immutable server FX quote; never trust a submitted converted total. Manual overrides are explicit and retain their provenance. If a quote cannot be obtained, retain the original expense with `conversion:null`, and mark total/balances incomplete rather than inventing a rate. Repayments may initially be entered in the reporting currency. A home-currency change with financial records requires explicit revaluation; v1 rejects it rather than silently changing balances.

Invitation URLs must use a configured origin/application link; otherwise return `url:null` and expose a local share/code flow. Do not invent a deployed URL. Never accept membership solely from a client-supplied traveller name or ID.

## Numeric and collection bounds

Every amount/budget, including a converted home amount, is a nonnegative integer no greater than `999999999999` minor units. Expense and repayment amounts must be positive. A trip has at most 10,000 expenses and repayments combined. Rates have at most 18 significant digits and at most 18 fractional digits. These bounds allow exact Swift Decimal conversion and safe Int64 aggregate arithmetic. SQL/TypeScript may use larger integer representations internally, but must enforce the transport bounds. Settlement suggestions sort creditors/debtors by descending initial amount with ascending ID tie-break, then consume each list in order without re-sorting after a transfer.

The v1 trip directory returns one complete snapshot per page to bound Worker memory; clients follow `nextCursor` until null. Rate lookup is public with an IP-based rate limit so local-only users can convert amounts before signing in. It contains no user expense data. `FXTable` lists every supported reference rate from one base so clients can convert between any pair offline, such as the watch's quick convert. It is indicative and edge-cached, not stored: expenses still cite an immutable `FXQuote`.


## Contract ownership and expressiveness

The API owns this contract. Hono route definitions reference the canonical Zod schemas; API TypeScript types are inferred from them in [`src/types/contract.ts`](../src/types/contract.ts). Clients may generate their own language models from [`contracts/openapi.json`](../contracts/openapi.json), but those generated models are not the source for API implementation types. Run `bun run contracts:generate` after a deliberate schema change. `bun run contracts:check`, also included in `bun run check`, rejects stale artifacts and validates representative JSON with an independent JSON Schema 2020-12 implementation.

OpenAPI describes fields, required and nullable values, operation variants, supported currency codes, ordinary scalar/collection bounds, bearer authentication and HTTP methods. In particular, a nullable field is still required unless stated otherwise: `paidOn`, `conversion`, nullable leg references, nullable sync cursors/epochs and `SyncResponse.snapshot` cannot simply be omitted. `Stop.timeZone` has different semantics: it may be omitted, but it cannot be null. The API's parsed TypeScript output also omits explicit `undefined` rather than storing an undefined-valued property.

Runtime validation additionally checks real Gregorian dates within 1900–2200, known IANA time-zone names, trimmed nonempty text, and exact positive rates with at most 18 significant and 18 fractional digits. OpenAPI annotations describe these constraints, but a generated client must not assume a successful structural JSON Schema check establishes all of them. The first query parameter value is used when a name is repeated; FX requires `from`, `to` and `date`, although its parser retains empty defaults to preserve the existing error order. Streamed request byte limits, fatal UTF-8 decoding, rate limits, maintenance and Apple configuration checks are middleware or service behavior, not JSON Schema rules.

Trip graph rules remain in runtime validation: IDs must be unique within their entity kind, linked entities/travellers must exist, day ownership follows ordered stop nights, paid status agrees with the payment date, the owner is active, and expenses plus repayments must remain within the combined 10,000-record limit. Durable Object transactions additionally enforce membership, owner privileges, revision/epoch checks, receipt hashes and tombstones. Ledger arithmetic, FX provenance, omission-preserving updates, deletion cleanup, ownership transfer and WebSocket membership rechecks depend on state and cannot be represented by a generated transport model. Keep the Workers tests and money fixtures alongside client contract checks.
