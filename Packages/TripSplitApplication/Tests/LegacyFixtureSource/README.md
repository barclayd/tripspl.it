# Original app-module store fixture

`TripSplit-build5.store` is a synthetic SwiftData store created with the unchanged original `LocalDocument` model compiled under the pre-extraction Swift module name `TripSplit`. It contains no credentials or real account data. Its entity schema hash also matches the actual iOS build-5 schema: `dd4a08fa92dbc34add26967c40200ed2143cb5528e7ba80f5cb2309c71c3b807`.

The fixture has four documents: one account-bound trip with two pending operations (one attempted and immutable, one conflicted) and restore-review state; one local trip with a frozen create snapshot and operation identity; an expense draft; and onboarding state. `documents.json` preserves the exact JSON payload bytes as base64 for comparison. `expected.json` names the key identities.

Reproduce in a clean temporary directory by copying `LegacyStore.swift` and `../TripSplitApplicationTests/Fixtures/documents.json`, then running:

```sh
xcrun swiftc -parse-as-library -module-name TripSplit LegacyStore.swift -o create-legacy
./create-legacy "$PWD"
```

This writes `legacy.store`; use SQLite's backup API to copy it to `TripSplit-build5.store` after the creator exits. The resource committed to tests must be copied to a temporary directory before opening it, because SwiftData may update store metadata even on reads. Never regenerate it with the extracted `TripSplitPersistence.LocalDocument`: the old module identity is the point of this regression fixture.
