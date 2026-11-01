# Verification and delivery

- Run relevant test suites and platform builds locally before delivering changes. Record the tested source revision and results.
- Keep pull-request CI fast: API types, generated contracts and destination-data consistency only. Do not add duplicate test suites, native builds, watchOS compilation or validation on every merge to `main`.
- Hosted TestFlight delivery may skip tests already completed locally for the source being released. Keep archive/export, signing, upload and exact-build availability checks.
- Repeat local tests when source changes affect their coverage or a failure remains unresolved; do not rerun unchanged suites just to duplicate CI.
