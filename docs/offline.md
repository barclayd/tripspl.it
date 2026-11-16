# Local-first behaviour

Trips, their itinerary and traveller details, expenses, repayments, budget and archive state are saved to the device before sync. The ledger is calculated from the confirmed snapshot plus the durable local outbox, so logging, editing, deleting and checking balances work without sign-in or signal. Drafts and the outbox survive app restarts. Account-bound trips remain visible while an expired session needs reauthentication, but are hidden from another signed-in account.

The audit found and fixed these gaps:

| Area | Behaviour |
| --- | --- |
| Foreign-currency expense save | Uses the last cached rate immediately. With no rate, saves the original amount and marks totals incomplete; fills the conversion when rates return. Bank charges and existing conversions stay fixed. |
| Home and first-trip conversion cards | Use the same persistent rate cache as the full converter, including quotes fetched before any expense existed. |
| Editing after a failed upload | Preserves the attempted operation exactly and queues later edits separately. Only unsent edits of the same record coalesce. Archive and settings changes no longer replace each other. |
| Trip deletion | Hides the trip immediately and retains a persisted deletion marker until acknowledgement. An uncertain trip creation replays its frozen request before deletion, preventing a late create from resurrecting it. |
| Reconnect during sync | Requests another pass instead of dropping the trigger. Transient failures retry with backoff from 2 to 60 seconds, keeping original operation identities. |
| Watch-to-phone changes | Persist before transport, retain watch save times on delivery, and use cached FX on the phone. Acknowledgements identify the particular edit so an earlier reply cannot clear a newer queued change. |
| Competing edits | The latest saved edit wins for each record, independent of upload order. Persistent clocks and operation IDs break ties; delayed deletes/inserts and lost acknowledgements converge. Derived FX fills never count as a newer user edit. |

Foreground, connectivity changes and live-trip hints trigger sync. On backgrounding, the phone submits a network-required `BGProcessingTaskRequest`; it cancels work on expiration and leaves unacknowledged operations queued. **iOS chooses when background work runs** and may defer it, especially after force-quitting or disabling Background App Refresh. Reopening the app starts sync immediately. This is not a promise to wake a suspended app at the exact moment signal returns.

Restored installations and changed server recovery epochs still require review. Invalid edits that would break itinerary/financial references stay reviewable. Already-attempted operations from older versions have no original edit timestamp and retain their existing revision conflict handling; new edits use the new protocol. Device clocks must be reasonably correct for ordering independently made offline edits; observed server clocks prevent a clock adjustment on one device from moving its subsequent edits backwards.

Sign-in, joining or issuing invitations, removing linked memberships, account deletion and sending nudges require the server. These change authenticated access or contact other people. Bundled destination search and manual origin selection remain usable offline; Apple Maps search, reverse geocoding, fresh map imagery and new FX rates require a connection. Previously cached trips and rates do not depend on those services.

# Release and device checks

Deploy the compatible API before distributing the new client: its strict schemas must accept `editedAt` and `conversionOnly`, and clients must understand terminal `superseded`. The SQLite version table is created additively; legacy requests and stored snapshots continue to work.

On a signed phone build, use a synthetic trip and check:

1. Enable Airplane Mode, create a trip, add/edit/delete an expense, record a repayment, and restart. Changes and balances remain available. With no cached rate, a foreign expense still saves and totals show the rate is pending.
2. Delete a synced trip offline and restart. It remains hidden. Reconnect and verify the deletion on the other device.
3. Edit the same expense on two devices at different times, uploading the older edit last. Both devices end with the later edit. Edit different expenses and confirm both survive.
4. Edit on the watch while the phone is unreachable, then make a newer phone edit. Reconnect: the watch edit keeps its original save time and does not replace the newer one.
5. Reconnect with the app open to verify immediate sync and FX fill. Separately exercise OS-scheduled background processing on device; simulator builds and unit tests do not establish when iOS will grant runtime.
