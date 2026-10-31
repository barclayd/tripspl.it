# TripSplit for iPhone and iPhone Duo

Native SwiftUI app, iOS 26 minimum, built with Xcode 27.1. XcodeGen owns the project configuration; the generated project is included for opening directly in Xcode. No Apple team or provisioning identifier is hard-coded.

```sh
cd ios
xcodegen generate
xcodebuild -project TripSplit.xcodeproj -scheme TripSplit \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/tripsplit-ios-build CODE_SIGNING_ALLOWED=NO build
swift test
xcodebuild -project TripSplit.xcodeproj -scheme TripSplit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO test
```

Tests use the canonical money/currency fixtures in `../contracts/`. The native suite also tests SQLite restart, restored installation identity, immutable uncertain operations, multi-batch sync, conflicts, account isolation and JSON null encoding. The `Domain` directory is Foundation-only and runs as a Swift package on macOS.

## Run and configure

The app opens empty. The explicit `--demo` launch argument seeds an empty store with sample trips and labelled manual conversion estimates. Demo data is never injected into an existing store. To launch an installed simulator build:

```sh
xcrun simctl launch <simulator-udid> it.tripspl.TripSplit --demo
```

Set `TRIPSPLIT_API_BASE_URL=https://your-configured-service` in the build settings (origin, without `/v1`). With no service configured, local trip creation, editing, manual conversion, splitting and repayment records work; cloud features show a setup state. Public reference FX is available without signing in when the service is configured.

A Debug build accepts `--api-base-url http://127.0.0.1:8787` or `http://localhost:8787` for a local Worker. Release ignores that argument and only accepts HTTPS from build configuration. ATS has the narrow local-network setting, without arbitrary loads. This is transport configuration only; it adds no authentication bypass.

For a device/TestFlight build, choose the authorised Apple team and enable Sign in with Apple for `it.tripspl.TripSplit`. The Apple entitlement is included; credentials, signing certificates, provisioning and server Apple audience/secrets are external configuration. Universal links additionally need an explicitly authorised Associated Domains entitlement and matching server AASA configuration. No domain or team prefix is invented. The fallback invitation format is `tripsplit://invite/<tripId>/<inviteId>#token=<secret>`; the bearer token stays in the URL fragment.

Unsigned simulator builds may not have Keychain access. The nonsecret installation identity falls back to a backup-excluded cache marker. Cache loss conservatively triggers restore review. **Sessions always remain in nonsynchronising, device-bound Keychain storage; no credential fallback exists.** Native Apple authentication needs a correctly signed build and server setup to verify end to end.

## Persistence and sync

SwiftData uses `cloudKitDatabase: .none`. Each trip document contains its confirmed snapshot, pending operations, account binding and restore state. An edit and its operation save atomically as one document. Normal backup includes trips, drafts and pending operations. A recreated installation requires a server snapshot and explicit review before old edits are uploaded; epoch changes keep each original draft for conflict resolution.

Pending commands retain their IDs and exact payload once attempted. Unsent edits can coalesce. Editing an item whose command is awaiting acknowledgement retains the new editor draft and explains why its next save must wait. Conflict review compares local/server values and offers explicit discard or reapply. Creation freezes its initial payload and owner identity before the request; subsequent records drain in batches of at most 50. Foreground, network reconnection and authenticated WebSocket hints trigger authoritative snapshot sync.

Trips bound to an account are hidden from other accounts and cannot upload into them. Local unbound trips remain available before sign-in. Sign-out retains account-bound data; successful account deletion requests clear it. Sign-out first refreshes expired credentials, and always clears the local session; if the service is unreachable it explicitly reports that remote revocation could not be confirmed. Archive removes a trip from the main list but retains its data and server history.

## Native presentation

The trip/day selection and editor drafts live above the adaptive layout. `NavigationSplitView` and system `TabView`/toolbars supply iPhone and Duo chrome; iOS 27 APIs are guarded. Closed shows the selected task, wide shows its parent alongside, and a short landscape day highlights the total beside its items. The map camera remains in app state. Custom travel motifs are native SwiftUI: boarding passes, departures flaps, passport stamps, expense receipt and luggage tags. Reduce Motion removes spatial receipt/pass transitions; system text styles and accessibility labels cover controls.

The initial itinerary is built with stable day/leg IDs and a user-visible trip time zone. Settings allow title, budget, time zone and traveller changes. Editing the stop sequence/durations after creation is deliberately not exposed yet: it needs an explicit financial-record reassignment workflow, and the app does not silently move expenses. Current financial operations can move an individual expense between existing days/legs in its editor.

## Release checks still requiring external configuration

- Signed-device Apple sign-in, token rotation/revocation, cloud multi-user invites and live collaboration.
- Associated-domain ownership/AASA and real universal-link opening.
- Device ergonomics and real Duo fold/hinge behavior; simulator coverage is not device verification.
- App Store privacy declarations, production service credentials and authorised TestFlight delivery.
