# TripSplit for iPhone and iPhone Duo

Native SwiftUI app, iOS 26 minimum, built with Xcode 27.1. XcodeGen owns the project configuration; the generated project is included for opening directly in Xcode. The authorised Apple team is `R2GGK3VN2C`; provisioning profiles remain managed by Xcode.

```sh
cd apple/ios
xcodegen generate
xcodebuild -project TripSplit.xcodeproj -scheme TripSplit \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/tripsplit-ios-build CODE_SIGNING_ALLOWED=NO build
swift test --package-path ../Packages/TripSplitDomain
swift test --package-path ../Packages/TripSplitApplication
xcodebuild -project TripSplit.xcodeproj -scheme TripSplit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO test
```

Tests use the canonical money/currency fixtures in `../../api/contracts/fixtures/` and `../../api/src/data/currencies.json`. The native suite also tests SQLite restart, restored installation identity, immutable uncertain operations, multi-batch sync, conflicts, account isolation and JSON null encoding. The package tests include a synthetic store created by the old app module and a consumer using only public APIs.

## Shared packages

The app is a composition shell for four local packages in `../Packages/`: `TripSplitDomain`, `TripSplitInfrastructure`, `TripSplitApplication` and `TripSplitFeatures`. Infrastructure exposes networking, persistence and sync separately. Features exposes design system, shared UI, Apple adapters and six vertical UI products. See [the architecture and dependency rules](../../docs/architecture.md#package-architecture) before adding a feature.

Domain, networking, persistence, sync, application coordination and conversion are usable without iOS presentation code. Their minimum platforms are iOS 26, macOS 26 and watchOS 26. Run macOS package tests locally; when changing shared services, also compile the affected products for watchOS. CI keeps only fast validation and does not repeat these builds or tests. The Apple Watch app is in [`../watch/`](../watch/README.md) and shares this project; a Mac interface remains future work.

From `apple/ios/`, check the watchOS consumers with:

```sh
swift build --package-path ../Packages/TripSplitApplication \
  --scratch-path /tmp/tripsplit-watch-packages \
  --triple arm64_32-apple-watchos26.0 \
  --sdk "$(xcrun --sdk watchos --show-sdk-path)" \
  --target TripSplitApplication
swift build --package-path ../Packages/TripSplitApplication \
  --scratch-path /tmp/tripsplit-watch-packages \
  --triple arm64_32-apple-watchos26.0 \
  --sdk "$(xcrun --sdk watchos --show-sdk-path)" \
  --target TripSplitConversion
```

## App icon

`TripSplit/AppIcon.icon` is the editable Icon Composer source. It preserves the original boarding pass, hand-drawn airplane, barcode, perforations and rose (`#E5266B`) as four SVG layers. The `Boarding pass` group is scaled to 118.8%, reduced 10% from the previous 132% version to leave more padding inside Apple's masks. The artwork is rotated 20° anticlockwise from its original 10° clockwise angle, so its final angle is −10°. Adjust the group scale in Icon Composer to resize all details together.

The document supports iOS and watchOS, with a near-black dark background (`#101012`), explicit foreground colours and contrasting monochrome layer fills so the airplane stays visible when the system applies clear or user-selected tints. Apple supplies the outer masks and Liquid Glass effects. XcodeGen includes the `.icon` bundle as a single resource; it replaces the old bitmap app-icon asset. The Watch rendering can be previewed in Icon Composer; this repository does not yet contain a watchOS app target.

## Run and configure

The app opens empty. The explicit `--demo` launch argument seeds an empty store with sample trips and labelled manual conversion estimates. Demo data is never injected into an existing store. To launch an installed simulator build:

```sh
xcrun simctl launch <simulator-udid> it.tripspl.TripSplit --demo
```

Debug builds also accept `--sync-recovery-demo`: an isolated, in-memory account with three unsent expenses and a simulated rejected refresh. It opens Account & sync to verify the sign-in recovery screen and local drafts without using saved credentials or contacting the service. Apple sign-in itself is not simulated as a success.

The default service is `https://api.tripspl.it`, configured by `TRIPSPLIT_API_BASE_URL` in `project.yml` (origin, without `/v1`). Its health endpoint and public reference FX have been verified against the deployed Worker. Currency conversion works without signing in. The server’s Apple credentials and audience are configured, and its challenge endpoint is live. The full signed-device sign-in flow remains to be verified. Private trip endpoints require authentication.

To use another environment, override `TRIPSPLIT_API_BASE_URL` in the build settings. Clearing it leaves local trip creation, editing, manual conversion, splitting and repayment records available with an explicit cloud setup state.

A Debug build accepts `--api-base-url http://127.0.0.1:8787` or `http://localhost:8787` for a local Worker. Release ignores that argument and only accepts HTTPS from build configuration. ATS has the narrow local-network setting, without arbitrary loads. This is transport configuration only; it adds no authentication bypass.

The project uses team `R2GGK3VN2C` and bundle ID `it.tripspl.TripSplit`, with Sign in with Apple and `applinks:api.tripspl.it` entitlements. Xcode created an explicit development profile from the existing signed-in account. If command-line provisioning reports “No Accounts”, open this project’s Signing & Capabilities pane in Xcode so it can create or refresh its managed profile. The matching AASA is served by the Worker. Signing secrets and profiles stay outside Git. The fallback invitation format is `tripsplit://invite/<tripId>/<inviteId>#token=<secret>`; the bearer token stays in the URL fragment.

Unsigned simulator builds may not have Keychain access. The nonsecret installation identity falls back to a backup-excluded cache marker. Cache loss conservatively triggers restore review. **Sessions always remain in nonsynchronising, device-bound Keychain storage; no credential fallback exists.** Native Apple authentication needs a correctly signed build and server setup to verify end to end.

## Persistence and sync

SwiftData uses `cloudKitDatabase: .none`. Each trip document contains its confirmed snapshot, pending operations, account binding and restore state. An edit and its operation save atomically as one document. Normal backup includes trips, drafts and pending operations. A recreated installation requires a server snapshot and explicit review before old edits are uploaded; epoch changes keep each original draft for conflict resolution.

Pending commands retain their IDs and exact payload once attempted. Unsent edits can coalesce. Editing an item whose command is awaiting acknowledgement retains the new editor draft and explains why its next save must wait. Conflict review compares local/server values and offers explicit discard or reapply. Creation freezes its initial payload and owner identity before the request; subsequent records drain in batches of at most 50. Foreground, network reconnection and authenticated WebSocket hints trigger authoritative snapshot sync.

Trips bound to an account are hidden from other accounts and cannot upload into them. Local unbound trips remain available before sign-in. Sign-out retains account-bound data; successful account deletion requests clear it. Sign-out first refreshes expired credentials, and always clears the local session; if the service is unreachable it explicitly reports that remote revocation could not be confirmed. Archive removes a trip from the main list but retains its data and server history.

## Native presentation

The trip/day selection and editor drafts live above the adaptive layout. Narrow windows use one `NavigationStack` for Trips → trip → day/travel, so Back preserves the parent trip. Wide landscapes use `NavigationSplitView` to show the parent alongside. System `TabView`/toolbars supply iPhone and Duo chrome; iOS 27 APIs are guarded. Closed shows the selected task, and a short landscape day highlights the total beside its items. The globe feature owns map camera state. Custom travel motifs are native SwiftUI: boarding passes, departures flaps, passport stamps, expense receipt and luggage tags. Reduce Motion removes spatial receipt/pass transitions; system text styles and accessibility labels cover controls.

Portrait day pages have a centred date carousel with calendar dates and trip-day numbers. Swipe left through the content or header for the next day, right for the previous, or tap/scroll the date strip. Landscape keeps the sidebar. The trip name and flag sit above the selected day's city; the organiser can tap the city to choose a one-day location from the destination catalogue or Apple Maps, or restore the itinerary location. These edits persist offline and sync independently per day. They do not move expenses, change overnight stops or change the stop's currency.

The initial itinerary is built with stable day/leg IDs and a user-visible trip time zone. Settings allow title, budget, time zone and traveller changes. Editing the stop sequence/durations after creation is deliberately not exposed yet: it needs an explicit financial-record reassignment workflow, and the app does not silently move expenses. Current financial operations can move an individual expense between existing days/legs in its editor.

Quick Convert opens with the current stop's currency and the trip's home currency. Both sides can be changed by searching countries, cities, currency names/codes or flag emoji; the selected place keeps its flag, and countries with multiple currencies offer separate choices. Swap retains the entered amount and the trip shortcut restores the opening pair. Only the inline home card is hidden when today's currency matches home; trip/day navigation remains available. Identical currencies convert offline at 1:1. Pair changes discard old quotes and manual rates, and only a conversion into the trip's home currency can be carried into an expense's home amount.

Expense day pills toggle multiple dates for stays and other daily costs. The entered amount is the total shared evenly across those days, with exact minor-unit rounding in both currencies. Opening any day’s share edits the whole expense; moving it through the day actions assigns the whole total to the destination day. Travel legs stay exclusive. The custom amount pad starts focused, then hides when tapping elsewhere, scrolling or editing another field. Tapping the amount shows it again; dismissing the software keyboard leaves it hidden.

Foreign-currency expenses automatically use the latest available reference rate, requesting the current UTC date even for future itinerary days. Offline saves use the newest cached quote or dated rate-table estimate. Reopening an expense lets the traveller enter, change or clear the exact bank charge in their home currency; saved charges and estimates stay fixed during later rate refreshes. Older expenses without conversions are repaired on launch, foreground and reconnection, respecting outstanding sync operations and restore review. If no rate has ever been available for the pair, the editor keeps the draft and asks for a connection or a home amount.

## Remaining release checks

- Verify signed-device Apple sign-in, token rotation/revocation, cloud multi-user invites and live collaboration; the supplied Apple key is associated with this app’s primary App ID.
- Verify real universal-link opening after Apple fetches the association file.
- Device ergonomics and real Duo fold/hinge behavior; simulator coverage is not device verification.
- Complete App Store privacy declarations before any public release. Internal TestFlight delivery is configured for Dan; installation and device acceptance remain separate checks.

## Internal beta delivery

App Store Connect app `6829340844` is **TripSplit: Travel Budget**; the installed name remains TripSplit. The intended internal group is **Dan**, ID `69183108-1726-4905-82c5-e3e6ecae0251`. Nonsecret release settings live in `testflight.json` alongside this README. The Apple release entrypoint is `apple/scripts/testflight.py`; its project path is relative to the repository root. Run the commands below from that root.

Use the shared `testflight-release` skill and tools from `~/Developer/barclayd` (`./codex/install-testflight.sh`). The normal local route is manual distribution signing and App Store Connect API authentication, with no Organizer or Safari dependency:

```sh
python3 apple/scripts/testflight.py check
python3 apple/scripts/testflight.py release --dry-run
python3 apple/scripts/testflight.py release
python3 apple/scripts/testflight.py release --state /private/path/build.json
python3 apple/scripts/testflight.py resume --receipt /private/path/release.json
python3 apple/scripts/testflight.py status --receipt /private/path/release.json
```

Run from a clean committed checkout. `check` and `release` unlock the dedicated signing keychain, restore its codesign access, sign and verify a temporary test bundle, and install every configured target's profile before any tests run. This catches a wrong keychain password, unavailable private key or missing local profile before a long build. Protected diagnostics identify the failed stage. `release --dry-run` only inspects the plan; it does not unlock, install or prove signing works.

`release` then runs the scheme's tests, resolves the next remote build number, archives/exports an internal-only IPA, uploads it once and performs a bounded availability check. It holds a local release lock through upload and reuses `~/Library/Caches/TripSplit/TestFlightDerivedData`; do not routinely clean this cache. The build number is an archive override, not a source edit. A source change during tests, archive or export stops the next stage.

The command prints a private `build.json` checkpoint before building. After a test, archive or export failure, use `release --state` with that file. Successful tests and artifacts are reused only with the same clean source SHA, release configuration and Xcode version, and matching content hashes. Failed attempts keep separate logs and artifacts. A failed archive gets a fresh remote build-number lookup; if another release consumes an already archived number, upload stops. Do not edit checkpoints to bypass these checks.

To exercise signing and recovery without another TestFlight upload, use `release --stop-after tests`, then `release --state /private/path/build.json --stop-after archive`, then `release --state /private/path/build.json --stop-after export`. Each stops at a saved checkpoint. `--stop-after export` produces a signed internal-only IPA locally; it does not reserve the number at Apple. Only a subsequent release command without `--stop-after` uploads it.

Signing assets live in `~/.config/testflight/signing/tripsplit` (override with `TRIPSPLIT_SIGNING_DIR`): `codex-testflight.keychain-db`, `keychain-password` and an App Store profile for each target under `targets` in `testflight.json`: `AppStore.mobileprovision` for the app, `AppStoreWidgets.mobileprovision` for its widgets, plus `AppStoreWatch.mobileprovision` and `AppStoreWatchWidgets.mobileprovision` for the embedded watch app and its complications. The app and widget profiles need the `group.it.tripspl.TripSplit` App Group assigned to their identifiers on the developer portal; the API can enable App Groups but not assign a group. API profile `codex-testflight` is selected explicitly. The profiles must match their targets and the team, share the one distribution identity and remain valid. The archive is checked to contain exactly those targets before export. The App Manager key cannot use the team's cloud-managed signing certificate, and command-line Xcode did not see the account used by Organizer; use the prepared manual identity. Do not use the Sign in with Apple key as an App Store Connect API key.

Receipts, checkpoints and logs are private under `~/.local/state/testflight/tripsplit`. Exit 7 means Apple is still processing or enabling access. Resume the same `release.json` receipt; never rerun the entire release merely to wait for processing. `release --state` also follows an existing matching receipt without rebuilding or uploading. If upload was attempted but no receipt exists, it refuses another upload: reconcile the exact version/build using the shared `testflight track` helper first. A receipt records source SHA, actual IPA hash, version/build, Apple build ID and verified group access. API read retries are bounded; uploads are not automatically retried.

For unattended use, keep the Mac's existing login session and signing files available. These commands do not change the login/default keychain, Apple account, sleep or lock settings. The dedicated keychain was recovered on 6 November 2026 from the existing exported identity; the previous keychain/password are retained in a private `backup-*` directory alongside the signing assets. Passwords stay in protected files and never appear in command arguments. A repair must preserve the original assets and verify the replacement can sign before switching to it.

Build **1.0 (7)** proved CLI archive, manual signed export, API upload and exact-build availability checks on 1 November 2026, from source `353939ce57a6f92a560e4f4745903531f601a857`. Apple reported VALID and IN_BETA_TESTING with Dan-group access. This does not claim physical-device installation.

### Hosted releases

The manual `testflight.yml` GitHub Actions workflow calls the shared, commit-pinned macOS workflow. It sets `run-tests: false` to avoid repeating local tests: run the relevant checks on the committed release revision and record its SHA/results before dispatch. CI still checks Apple access, archives, signs, uploads and verifies the exact build's availability. The repository's `testflight` environment contains the ASC key, exportable distribution identity/password and App Store profile as secrets. It uses a temporary keychain and removes temporary signing material afterwards. Only the release receipt is retained as an artifact.

After the workflow is merged to the default branch, trigger it with `gh workflow run testflight.yml --ref main` (or an authorised branch), then follow the returned run. Hosted execution is unverified until its first successful run; the local CLI path and CI signing prepare/cleanup have been exercised. The shared workflow signs with a single profile, so it can't release the app with the watch app embedded until it takes a profile per target like the local script. Coordinate local releases with CI—the build-number lookup is not a cross-machine reservation. Keep the caller's `uses` and `tooling-ref` on the same reviewed shared-tooling commit.
