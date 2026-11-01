# TripSplit for Apple Watch

Native SwiftUI watch app, watchOS 26 minimum, built with Xcode 27.1 from the same XcodeGen project as the iPhone app (`../ios/project.yml`, target and scheme `TripSplitWatch`). This folder holds only the app shell: lifecycle, configuration and assets. Screens live in `../Packages/TripSplitWatchFeatures`; the watch state lives in `TripSplitApplication`'s `TripSplitWatchModel` product.

```sh
cd apple/ios
xcodegen generate
xcodebuild -project TripSplit.xcodeproj -scheme TripSplitWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)' \
  -derivedDataPath /tmp/tripsplit-watch-build CODE_SIGNING_ALLOWED=NO build
xcrun simctl install <watch-udid> \
  /tmp/tripsplit-watch-build/Build/Products/Debug-watchsimulator/TripSplitWatch.app
xcrun simctl launch <watch-udid> it.tripspl.TripSplit.watchkitapp --demo
```

`--demo` shows the same sample trips as the phone's `--demo`, plus spend on the past trips so the passport has a total. Without it the watch shows the phone's mirrored trips, or the empty state until the phone has shared one.

The watch packages have no macOS tests of their own. Compile them for watchOS, and test the watch model with the macOS application tests:

```sh
swift build --package-path ../Packages/TripSplitWatchFeatures \
  --scratch-path /tmp/tripsplit-watch-packages \
  --triple arm64_32-apple-watchos26.0 \
  --sdk "$(xcrun --sdk watchos --show-sdk-path)"
swift test --package-path ../Packages/TripSplitApplication
```

## Companion

The iPhone stays the source of truth. `WatchCompanionHost` (in `TripSplitApplication`'s `TripSplitCompanionHost` product) publishes the phone's trips as a `CompanionContext` whenever they change. `CompanionSession` sends it LZFSE-compressed through `updateApplicationContext`, falling back to `transferFile` for large contexts. The watch keeps the latest context, cached rates and its queued changes in the `group.it.tripspl.TripSplit` App Group so the app and complications open instantly and offline.

Changes made on the watch are `CompanionCommand`s sent with `transferUserInfo`. The watch overlays them on its trips until the phone's next context reflects them. The phone applies them through the same local store, pending-operation queue and sync as its own edits, skips re-delivered commands, and returns any it cannot apply in `CompanionContext.rejected` with a reason to show.

Quick convert (C) dials an amount between today's stop currency and home with the Crown, or any pair the wearer picks. Rates come from the API's daily reference table (`GET /v1/fx/rates`), cached per base currency and refreshed when the app becomes active, so any two listed currencies convert offline through the base. A fresher per-pair quote wins over the table, and the latest rate recorded on an expense is the last fallback. The last pair and amount are remembered between launches.

## Delivery

The watch app is not embedded in the iPhone app or its TestFlight builds yet. That needs provisioning profiles for `it.tripspl.TripSplit.watchkitapp` and the App Group, and multi-profile signing in the release workflow.

## TripSplit face

The iPhone app's Account & sync screen offers the "TripSplit" face (G4) through `CLKWatchFaceLibrary`, once a paired watch has TripSplit installed. Faces can only be made on a watch, so it's exported once and bundled:

1. On a watch with TripSplit, set up a face with four corner complications: Quick convert, Budget left, Who owes and Today
2. In the iPhone's Watch app, open it under My Faces, tap Share and save the `.watchface` file
3. Save it as `apple/ios/TripSplit/TripSplit.watchface` and run `xcodegen generate` in `apple/ios`, which adds it to the app's resources

Until the file's there, the Apple Watch section doesn't show.

## Design

The watch design handoff (Claude Design, `design_handoff_tripsplit_watch`) groups its screens by letter: A empty states, B trips list, C quick convert, D trip pages, E people, F log expense, G complications and H notifications. `TripSplitWatchDesign` holds its tokens (`WatchTheme`), type (`watchFont`, `boardFont`) and shared pieces such as the split-flap departure text.

Screens use the system font in its rounded and monospaced designs, scale with Dynamic Type, and swap the split-flap animation for a fade with Reduce Motion.
