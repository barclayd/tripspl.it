# TripSplit

A native iOS trip budget that keeps original currencies, planned costs, paid expenses and repayments distinct. Built for iPhone and iPhone Duo with offline entry, shared trips and Sign in with Apple.

## Architecture

- **App:** a thin SwiftUI iOS shell composed from local Swift Package Manager products
- **Shared Swift:** Foundation domain and accounting, networking, SwiftData persistence, explicit sync and independently composed feature UI
- **API:** Bun tooling, TypeScript, Hono and Zod on Cloudflare Workers; one SQLite Durable Object per trip, D1 for accounts and discovery
- **Sync:** Cloudflare serves both personal devices and shared trip members; automatic CloudKit sync is disabled
- **Recovery:** normal device backup eligibility for local drafts/pending edits, plus separate server recovery

See [destination data and currencies](docs/destination-data.md), [architecture](docs/architecture.md), [protocol rules](api/docs/protocol.md), [generated OpenAPI](api/contracts/openapi.json), [inferred transport types](api/src/types/contract.ts) and [shared money examples](api/contracts/fixtures/money-examples.json).

## Repository layout

```text
apple/
  ios/                 iPhone/iPad app shell and Xcode project
  Packages/            Shared Swift services and feature products
  scripts/             Apple build and TestFlight delivery tools
api/
  src/schemas/         Authoritative Zod request/response schemas
  src/data/            Currency metadata used by the API and Swift checks
  contracts/           Generated OpenAPI and shared accounting fixtures
  docs/                Protocol semantics
docs/                  Cross-platform architecture and data provenance
scripts/               Shared destination-data tools
```

Future Watch and Mac app shells belong under `apple/`; a web application will be a root-level `web/` sibling. The API owns the wire contract. TypeScript types and OpenAPI are derived from its Zod schemas; Swift keeps its local domain and persistence models independent of server implementation code.

## Development

The iOS project is generated with XcodeGen and builds with Xcode 27.1 or later. Ordinary iPhones target iOS 26; Duo presentation uses availability-gated iOS 27.1 APIs.

```sh
cd apple/ios
xcodegen generate
open TripSplit.xcodeproj
```

The API uses Bun 1.4.0 for dependency management and scripts. Node 24 or newer remains available for the Cloudflare `cf` CLI and its test/build tools. Cloudflare Workers is the deployed runtime. Install the locked dependencies, run the checks and start a local Worker:

```sh
cd api
bun install --frozen-lockfile
bun run check
bun run test
bun run dev
```

The Cloudflare API is deployed at [api.tripspl.it](https://api.tripspl.it/v1/health), with public exchange rates available before sign-in. Apple credentials and HTTPS invitation association are configured. Signed-device Apple sign-in and multi-user collaboration still need end-to-end verification. Local trip creation works without signing in. Never put credentials in the repository. Service configuration and deployment instructions live in [api/README.md](api/README.md).

## Swift packages

`apple/Packages/TripSplitDomain` owns models, exact money calculations, civil dates, shared transport values and bundled destination data. `apple/Packages/TripSplitInfrastructure` separates networking, persistence and sync. `apple/Packages/TripSplitApplication` coordinates those services. `apple/Packages/TripSplitFeatures` provides separate UI products, following the local-package and vertical-feature structure used by KeepFresh.

The reusable service layers are intended for iOS, watchOS and macOS consumers. Existing feature UI remains designed for iPhone and iPad; this repository does not yet ship a Watch or Mac app. New platforms compose their own presentation around the shared products. See [the dependency graph and migration plan](docs/architecture.md#package-architecture) for boundaries and extension guidance.

## Checks

```sh
swift test --package-path apple/Packages/TripSplitDomain
swift test --package-path apple/Packages/TripSplitApplication
xcodebuild -project apple/ios/TripSplit.xcodeproj -scheme TripSplit \
  -destination 'platform=iOS Simulator,name=iPhone Duo,OS=27.1' \
  CODE_SIGNING_ALLOWED=NO test
```

GitHub Actions checks both the Worker and the native app. Simulator and local checks do not establish successful Apple production sign-in or installed TestFlight delivery; those require their respective environments and credentials.
