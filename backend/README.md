# TripSplit backend

Strict TypeScript API on Cloudflare Workers, one SQLite `TripRoom` Durable Object per trip, and D1 for accounts, hashed sessions, immutable FX quotes and the trip directory. The HTTP and money contracts live in `../contracts/`.

## Local development

Use Node 24 or newer and npm. This project uses the `cf` CLI and its typed `cloudflare.config.ts`, with the Cloudflare Vite plugin; there is no Wrangler configuration or direct Wrangler dependency.

```sh
cd backend
npm ci
npm run check
npm test
npm run build
npm run dev
```

The local server defaults to `http://localhost:5173`. In another terminal:

```sh
npm run migrate:local
curl http://localhost:5173/v1/health
curl 'http://localhost:5173/v1/fx?from=GBP&to=GBP&date=2026-10-30'
```

`migrate:local` uses the Vite plugin's documented local Explorer API and rejects non-loopback destinations. This is necessary because `cf d1 migrations apply --local` currently requires a UUID, while Vite assigns the local binding the synthetic ID `DB-tripsplit-api`. The script applies the same SQL migrations transactionally, records their names, and is safe to repeat. Set `LOCAL_WORKER_ORIGIN` if the local dev port changes. Local state is under ignored `.cloudflare/state/`. No cloud resources are created by these commands.

The compatibility date is `2026-10-30`: the pinned workerd binary supports that date, but rejects `2026-10-31`. Upgrade the runtime and rerun checks before advancing it. Runtime tests use `@cloudflare/vitest-plugin`, real SQLite Durable Objects and D1; they do not mock the ledger storage. Apple/FX network responses are mocked and Apple test JWTs are cryptographically signed. No development login endpoint is shipped.

## Configuration and release

Authentication deliberately fails closed until the actual Apple configuration exists. Copy `.env.example` to ignored `.dev.vars` for local secrets. Configure nonsecret production bindings in `cloudflare.config.ts` and provide secrets through the deployment's secret store:

| Binding | Required value |
| --- | --- |
| `APPLE_AUDIENCE` | Enabled native Sign in with Apple bundle ID; proposed `it.tripspl.TripSplit`, verify the registered app |
| `APPLE_TEAM_ID`, `APPLE_KEY_ID` | Actual Apple team and Sign in with Apple key identifiers |
| `APPLE_PRIVATE_KEY` | PKCS#8 `.p8` signing key; a Worker secret |
| `SESSION_ENCRYPTION_KEY` | Base64 of 32 random bytes for AES-256-GCM encryption of Apple grants; a Worker secret |
| `INVITE_ORIGIN` | Provisioned HTTPS universal-link origin, or empty for code-only sharing |
| `APPLE_APP_ID` | Actual `TEAMID.bundle.identifier` for the association file; never a guessed ID |
| `MAINTENANCE_MODE` | Set to `1` during recovery to stop public requests, scheduled cleanup and projection alarms (health remains available) |
| `RECOVERY_EPOCH` | Positive increasing integer, initially `1`; increase after any server rollback |
| `DB` | Provisioned D1 database ID/name; apply `migrations/` before serving requests |
| `TRIPS` | `TripRoom` namespace, declared with SQLite storage in the export map |

Generate an encryption key locally with `openssl rand -base64 32` and store it directly as a secret. Back it up in the deployment secret manager: changing or losing it prevents existing Apple grant revocation and refresh. Key rotation requires re-encrypting stored grants before removing the old key.

The config declares the D1 database by name for an operator to provision/bind; it does not assume an account, resource ID, domain or working Apple credentials. Before an authorized deployment, inspect `cf d1 migrations apply --help`, apply `cf d1 migrations apply <actual-database-uuid> --dir migrations`, configure the Apple bindings/secrets, build, and deploy using the project's approved workflow. `cf` derives Durable Object lifecycle migrations from `exports.TripRoom`; keep the SQLite declaration on subsequent deployments. Cron must remain enabled (`*/5 * * * *`) for account cleanup and expired auth data. Logs/traces are enabled, with automatic invocation logs disabled to avoid collecting request URLs; application logs contain event names/error classes, never tokens or financial payloads.

Actual Apple sign-in, deployed D1/DO point-in-time recovery, associated-domain entitlement verification, and a production deployment require the real account configuration. They have not been claimed as live-provider verification by the local tests.

## API behavior

All endpoints are under `/v1` except the public invitation landing page and association file. Health, Apple challenge/sign-in, refresh and FX do not require a TripSplit access token. Trip data, sync, invitations and account deletion require one. Native WebSockets send the bearer token in the upgrade request's `Authorization` header. Do not put access or refresh tokens in URLs.

A challenge's raw random nonce is returned once. Native code hashes it with SHA-256 hex for Apple's request. The API validates Apple's RSA signature, issuer, audience, expiry and nonce, consumes the challenge once, exchanges the code and verifies the exchanged token's identity. Apple refresh grants are encrypted with account-bound authenticated data. Access/refresh tokens are random opaque secrets stored only as SHA-256 hashes. Access expires after 15 minutes, refresh after 30 days; refresh rotates both credentials atomically. Every refresh revalidates the Apple grant and returned identity, so a revoked Apple authorization cannot keep rotating TripSplit sessions indefinitely. Provider outages remain retryable; invalid/revoked grants revoke local sessions. There is no email/name-based account matching.

Limits are explicit: 1 MiB request bodies, 50 ordered operations per sync request, 40 travellers, 30 stops, 400 days, 100 travel legs, 10,000 combined expenses/repayments per trip, and 500 known trip targets per account. `/trips` returns **one complete snapshot per page** to bound memory at maximum trip size; continue `nextCursor` until null, including empty pages caused by removed memberships. Auth endpoints allow 30 requests/IP/minute, public FX 30/IP/minute, and authenticated requests 240/account/minute. Invalid and oversized requests do not apply operations. A large offline trip can be created with its itinerary/travellers and its financial records uploaded in bounded operation batches.

Each operation atomically checks membership, owner privileges where necessary, sync epoch, receipt hash and entity revision, then writes entity state/tombstone, history, directory outbox and receipt. Removed members cannot replay old operations or receive live hints. Exact repeats return `duplicate`; altered payloads with the same accepted ID return `OPERATION_REUSED`. Independent additions compose; competing edits return a conflict plus the current snapshot. Transient failures produce retryable HTTP errors, including if earlier operations in a batch committed: resend the same immutable IDs to recognize those receipts. Receipts and tombstones are retained for the trip's lifetime. The server never accepts a blind snapshot replacement after creation.

Itinerary updates preserve day/leg IDs and reject moving/deleting an expense's referenced date until that expense is explicitly moved. Ordered stop nights determine day ownership; the final return day belongs to the final stop. Reporting currency cannot change once financial records exist. Owner controls itinerary, settings, traveller identities and membership. Members may edit all financial records with persisted before/after audit history.

The authoritative ledger is independent of D1 directory availability. A persisted outbox is committed alongside membership and trip changes; an alarm is persisted before mutating state, retries failed projections, and applies revision/epoch-aware updates. `user_trip_targets` records create/join routing intent before authoritative membership is installed; list requests resolve each target against the TripRoom so a stale projection never grants access. Deletion uses the same durable targets to avoid missing a trip whose directory projection failed. WebSocket messages are hints; clients must always sync on foreground/reconnect. Sessions/membership are checked again before each hint, and maintenance closes expired connections.

## Money and FX

Amounts are positive integer minor-unit strings for expenses/repayments; zero is permitted for budgets. Maximum per-record/budget amount is `999999999999`. Calculations use `bigint`, half-up conversion and sorted-ID remainder allocation. `contracts/currencies.json` is the shared ISO 4217/SIX metadata: display-formatting conventions are not used for ledger precision (in particular, IDR has two minor digits). `contracts/money-examples.json` exercises both platforms' exact allocation, conversion and settlement behavior.

Public FX requests use [Frankfurter v2](https://frankfurter.dev/), with effective dates and immutable D1 quote IDs. The numeric JSON lexeme is read as decimal text, never converted through a binary floating-point number. Reference conversions are recomputed against the stored quote. Manual card-statement amounts remain explicit and may differ from the indicative rate. Unknown rates retain `conversion:null`; totals/debt are incomplete until resolved. Planned spending affects expected cost only; paid spending affects balances; repayments reduce balances without adding trip cost. Settlement ordering sorts initial debt/credit amounts descending, ties by traveller ID, then consumes them in order.

Invite secrets are hashed in SQLite, expire after seven days and are single-recipient. Reissuing an invite revokes the old unaccepted link. Acceptance links the authenticated account to the exact invited traveller; it never matches a name. HTTPS links use `/invite/<trip>/<invite>#token=<secret>` so the secret is not sent to web servers or included in request logs. If `INVITE_ORIGIN` is unset, `url:null` is returned for the native code-sharing flow.

## Account deletion

`DELETE /v1/me` with `{}` returns `202 {"status":"pending"}` after transactionally creating a durable deletion job, disabling the account and revoking sessions. Cleanup removes account membership, anonymizes its linked traveller, revokes invitations, and closes live access. Shared financial records remain balanced and attributable to “Deleted traveller”. If the account owns a shared trip, ownership transfers to the earliest remaining membership (ties by account ID). With no remaining linked accounts, the trip's financial/personal data is purged while minimal receipt/tombstone data prevents stale backup resurrection. Unclaimed traveller names do not grant ownership.

Apple grant revocation and cleanup retry with exponential delay (up to one day). A grant already revoked by Apple is treated as revoked. Provider outages leave the disabled account's job persisted; they do not cancel deletion. The `deletion_jobs` table is the operational queue to monitor for growing attempts. Deleted-account tombstones in each TripRoom stop an in-flight old create/join from reinstalling membership after cleanup.

## Recovery runbook

Cloudflare's [D1 Time Travel](https://developers.cloudflare.com/d1/reference/time-travel/) and [Durable Object SQLite PITR](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/#point-in-time-recovery-api) are separate from device backup. DO PITR is not supported by the local runtime; the tests simulate rollback/epoch transitions and exercise actual SQLite persistence/eviction.

1. Deploy `MAINTENANCE_MODE=1` before restoring. Capture current D1/DO bookmarks and the intended rollback time. Plan coordinated account/membership/session recovery; never treat an old D1 directory as authority.
2. Preview the exact D1 restore request with the current `cf d1 time-travel restore` command/schema before running it. For each trip's DO, the maintenance-only `recoveryBookmark(timestamp?)` and `restoreBookmark(bookmark)` RPCs wrap the documented storage PITR APIs and restart the object. Invoke them from a trusted operator Worker with the namespace binding; neither has a public HTTP route. Restoring aborts its current RPC as part of restarting the object, so verify the bookmark afterward.
3. **Increase `RECOVERY_EPOCH` before reopening traffic**, even if only D1 was restored. Rotate/revoke restored session rows and resume durable deletion jobs before accepting sign-in/sync. If D1 targets were lost while DO state was retained, invoke maintenance-only `repairDirectory()` on every affected object. It rebuilds targets and projections from authoritative memberships, and removes/anonymizes memberships for accounts explicitly marked for deletion. Missing D1 accounts stop repair with `RECOVERY_ACCOUNT_MISSING`; recover their identity mappings first rather than treating a rollback as account deletion. Enumerate namespace object IDs through the operator account if the restored D1 inventory is incomplete; the repair response returns each stored trip ID.
4. On access, each TripRoom detects the newer recovery epoch, persists a revision bump, records recovery in history and requeues its directory projection. New epochs take precedence over higher old projection revisions. Old client operation epochs receive `SYNC_EPOCH`; a complete snapshot is returned. Clients must preserve local drafts, reconcile against the recovered snapshot and explicitly review any replacement operation. Never mass-delete receipts/tombstones or automatically relabel stale operations with the new epoch.
5. Verify membership, one known expense/repayment, duplicate-operation behavior, discovery and deletion queues on an isolated recovery rehearsal. Deploy `MAINTENANCE_MODE=0` to resume traffic only after those checks. A restored database cannot recover writes newer than its selected bookmark; reconcile those with device drafts/history separately.
