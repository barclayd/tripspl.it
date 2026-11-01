# HTTP contract v1

JSON over HTTPS under `/v1`. Bearer access token required except challenge, Apple sign-in, refresh, health, exchange-rate lookup and public invite landing/association files. Error shape is `APIError`. IDs are opaque strings (client-created record/operation IDs use UUIDs). Timestamps are ISO 8601 UTC; civil dates use `YYYY-MM-DD`. All money/rates follow `tripsplit-v1.ts`. All lists, body sizes and batches are bounded. No credentials in query strings or logs.

| Method | Path | Request | Success response |
| --- | --- | --- | --- |
| GET | `/health` | — | `{ok:true}` |
| POST | `/auth/apple/challenge` | `{}` | `AuthChallenge` |
| POST | `/auth/apple` | `{challengeId, identityToken, authorizationCode, displayName?}` | `Session` |
| POST | `/auth/refresh` | `{refreshToken}` | `Session` |
| POST | `/auth/logout` | `{refreshToken}` | `{ok:true}` |
| GET | `/me` | — | `User` |
| DELETE | `/me` | `{}` | 202 `{status:'pending'}` or 200 `{status:'deleted'}` |
| GET | `/trips` | optional `cursor` | `{trips:TripSnapshot[], nextCursor:string|null}` |
| POST | `/trips` | `{operationId, trip:TripSnapshot}` | `TripSnapshot` |
| GET | `/trips/:tripId` | — | `TripSnapshot` |
| POST | `/trips/:tripId/sync` | `SyncRequest` | `SyncResponse` |
| POST | `/trips/:tripId/invites` | `{travellerId}` | `{id, token, expiresAt, url:string|null}` |
| POST | `/trips/:tripId/invites/:inviteId/accept` | `{token}` | `TripSnapshot` |
| DELETE | `/trips/:tripId/invites/:inviteId` | — | `{ok:true}` |
| DELETE | `/trips/:tripId/members/:travellerId` | — | `{ok:true}` |
| GET | `/fx` | `from`, `to`, `date` query parameters | `FXQuote` |
| GET | `/trips/:tripId/live` | WebSocket upgrade (authenticated) | `{type:'changed', revision, syncEpoch}` messages |

Apple challenge `nonce` is a random raw nonce. The app sends its SHA-256 hex digest to Apple's native request. The server checks that digest against Apple's token and consumes the matching challenge exactly once. Verify cryptographic signatures through a maintained library and Apple's keys; require configured bundle audience. Account deletion persists a cleanup job, invalidates app sessions and revokes the stored Apple grant, retrying temporary provider failures. It does not require a fresh Apple sign-in. Shared-trip records remain with account links removed and the linked traveller anonymised; ownership passes to the earliest remaining active member. Trips with no other linked member are removed. These consequences must be disclosed in the native confirmation.

Trip creation is idempotent on operation ID and trip ID, assigns the authenticated user to `ownerTravellerId`, and rejects impersonation. Ignore client-provided role/currentTravellerId as authority. `revision = 0` and `syncEpoch = 'local'` are permitted only in local draft creation; the server returns its own initial revision/epoch. Create must resolve the same original operation after uncertain acknowledgement.

For new entities `expectedRevision = null`; for edits it is the current confirmed entity revision. The server increments entity revisions; client payload revisions are never trusted. Trip settings use the confirmed trip revision. Financial operations can be sent independently even if unrelated expenses changed the trip revision. A stale sync epoch requires snapshot reconciliation; do not apply commands against an unknown epoch.

Sync requests process operations in order with an atomic transaction per operation. Conflicts/rejections are structured results, not silent drops. Include a snapshot if the cursor/epoch differs or there are results. Keep a rejected local draft visible. Revoked membership returns 403 and closes live subscriptions. Network errors and 5xx are retryable; never auto-retry a 409 conflict with a new revision.

The home-currency equivalent of same-currency expenses is `amountMinor`, regardless of conversion. For foreign-currency reference conversions, validate/recompute against an immutable server FX quote; never trust a submitted converted total. Manual overrides are explicit and retain their provenance. If a quote cannot be obtained, retain the original expense with `conversion:null`, and mark total/balances incomplete rather than inventing a rate. Repayments may initially be entered in the reporting currency. A home-currency change with financial records requires explicit revaluation; v1 rejects it rather than silently changing balances.

Invitation URLs must use a configured origin/application link; otherwise return `url:null` and expose a local share/code flow. Do not invent a deployed URL. Never accept membership solely from a client-supplied traveller name or ID.

## Numeric and collection bounds

Every amount/budget, including a converted home amount, is a nonnegative integer no greater than `999999999999` minor units. Expense and repayment amounts must be positive. A trip has at most 10,000 expenses and repayments combined. Rates have at most 18 significant digits and at most 18 fractional digits. These bounds allow exact Swift Decimal conversion and safe Int64 aggregate arithmetic. SQL/TypeScript may use larger integer representations internally, but must enforce the transport bounds. Settlement suggestions sort creditors/debtors by descending initial amount with ascending ID tie-break, then consume each list in order without re-sorting after a transfer.

The v1 trip directory returns one complete snapshot per page to bound Worker memory; clients follow `nextCursor` until null. Rate lookup is public with an IP-based rate limit so local-only users can convert amounts before signing in. It contains no user expense data.
