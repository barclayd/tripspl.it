# TripSplit

A native iOS trip budget that keeps original currencies, planned costs, paid expenses and repayments distinct. Built for iPhone and iPhone Duo with offline entry, shared trips and Sign in with Apple.

## Architecture

- **App:** SwiftUI, local SwiftData persistence and an explicit sync outbox
- **Backend:** TypeScript Cloudflare Workers, one SQLite Durable Object per trip, D1 for accounts and discovery
- **Sync:** Cloudflare serves both personal devices and shared trip members; automatic CloudKit sync is disabled
- **Recovery:** normal device backup eligibility for local drafts/pending edits, plus separate server recovery

See [architecture](docs/architecture.md), [HTTP contract](contracts/api.md), [transport types](contracts/tripsplit-v1.ts) and [shared money examples](contracts/money-examples.json).

## Development

The iOS project is generated with XcodeGen and builds with Xcode 27.1 or later. Ordinary iPhones target iOS 26; Duo presentation uses availability-gated iOS 27.1 APIs.

```sh
cd ios
xcodegen generate
open TripSplit.xcodeproj
```

The backend uses the Cloudflare `cf` CLI. Install dependencies, run the checks and start a local Worker:

```sh
cd backend
npm ci
npm run check
npm test
npm run dev
```

Cloud account, Apple sign-in and associated-domain configuration are required for live shared trips. Local trip creation works without signing in. Never put credentials in the repository. Backend-specific configuration and deployment instructions live in [backend/README.md](backend/README.md).

## Checks

```sh
swift test --package-path ios
xcodebuild -project ios/TripSplit.xcodeproj -scheme TripSplit \
  -destination 'platform=iOS Simulator,name=iPhone Duo,OS=27.1' \
  CODE_SIGNING_ALLOWED=NO test
```

GitHub Actions checks both the Worker and the native app. Simulator and local checks do not establish successful Apple production sign-in, a deployed backend or installed TestFlight delivery; those require their respective environments and credentials.
