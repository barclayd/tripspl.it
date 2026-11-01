# Offline destination catalogue

The 2026-11-01 catalogue contains **250 countries and territories** and **exactly 500 city or region destinations**, covering 242 country/territory codes. These are travel-search choices, not an official tourism ranking or the world's 500 largest cities. Country inclusion follows the current GeoNames country-code dataset: 252 source rows, excluding obsolete `AN` (Netherlands Antilles) and `CS` (Serbia and Montenegro), retaining `XK` (Kosovo). This count is not a claim about the number of sovereign states.

The app bundles four files in `ios/TripSplit/Domain/Resources/`:

- `Countries.json`: code, English display name, ordered current tender currency codes, representative latitude/longitude and search aliases.
- `Destinations.json`: stable `geonames-<ID>` identity, display name, country code, coordinates and search aliases.
- `DestinationTimeZones.json`: exact catalogue point-to-IANA mappings, scoped country zone choices, and explicit country representative defaults/provenance where available.
- `DestinationDataLicenses.txt`: GeoNames attribution and full CC BY 4.0 legal text, Google DSPL BSD notice and disclaimer, the full Unicode licence, and IANA's public-domain notice. The app's Settings screen displays this file offline under Place data & acknowledgements.

The data is about 309 KB combined, including licences. Countries have at most 16 aliases and destinations at most 12; the current generated data uses no more than 6 and 10 respectively. Full source dumps and XML are not app resources.

## Sources and versions

| Input | Version or snapshot | Purpose |
| --- | --- | --- |
| [GeoNames countryInfo.txt](https://download.geonames.org/export/dump/countryInfo.txt) | Retrieved 2026-11-01, exact bytes pinned | Current country/territory codes, ISO alpha-3 search aliases and continent membership |
| [GeoNames cities15000.zip](https://download.geonames.org/export/dump/cities15000.zip) | Retrieved 2026-11-01; original ZIP SHA-256 in `scripts/destination-data/upstream.json` | Destination identities, names, source aliases, coordinates, capital feature codes and population used only in limited regional selection |
| [GeoNames country dumps](https://download.geonames.org/export/dump/) | GR, ID, CH, IT and NZ ZIPs retrieved 2026-11-01; original ZIP hashes in `upstream.json` | Exact time-zone fields for the five selected destinations absent from the population-threshold city dump |
| [GeoNames linked-data features](https://www.geonames.org/ontology/documentation.html) | Six exact RDF responses pinned, retrieved 2026-11-01 | Bali province `1650535`, Zermatt `2657928`, Queenstown `6204696`, Santorini island `252919`, Amalfi `3183130`, and UM country-feature point `5854968` |
| [Google DSPL country coordinates](https://github.com/google/dspl/blob/db79dad685276dbf98ca44b875d1481bc240c5c1/samples/google/canonical/countries.csv) | Repository commit `db79dad685276dbf98ca44b875d1481bc240c5c1` | Country representative map points, with explicit exceptions below |
| [Unicode CLDR 49](https://github.com/unicode-org/cldr/releases/tag/release-49) | Release published 2026-10-21; commit `96e54b273d2da4ec6fbad350ba19ff23fa24a588` | English country/territory names, current tender currency records and Kosovo's scoped zone mapping in `metaZones.xml` |
| [IANA tzdb 2026f](https://data.iana.org/time-zones/tzdb-2026f/) | Exact `zone.tab`, `zone1970.tab`, `backward`, `version` and `LICENSE` bytes pinned | Complete country-scoped time-zone choices and equivalence of legacy aliases |
| `contracts/currencies.json` | Existing shared 165-code ISO minor-unit catalogue | Allowed currency codes for expense arithmetic and the country currency filter |

All downloaded source files, including licence texts, have exact SHA-256 hashes in `scripts/destination-data/source-hashes.json`. `upstream.json` records original URLs and pinned commits. GeoNames publishes a moving daily dump rather than an immutable release archive; therefore the repository contains a compact exact extract of the **501 source records** needed for the 500 destinations plus UM's representative point. A separate compact extract holds the 500 time-zone fields, and five exact TSV source rows preserve the supplemental country-dump records. The original large ZIPs are not needed to regenerate app resources. Their hashes and an extraction-check tool allow an auditor holding those original ZIPs to verify the compact sources against the original dumps and pinned RDF responses.

## Currency policy

Country lists mean **current CLDR tender currency as of 2026-11-01**, not every foreign currency a business may commonly accept. Import rules are:

1. Read `currencyData/region` in pinned CLDR `supplementalData.xml`.
2. Keep records whose `from`/`to` interval contains the snapshot date and whose `tender` flag is true; an absent flag defaults to true.
3. Keep only codes in the shared `contracts/currencies.json` catalogue, deduplicating without reordering. No active tender code is excluded by the supported-code filter in this snapshot.
4. Preserve CLDR source order. Do not infer a currency from a historical GeoNames country-info field, a neighbouring country, or commercial acceptance practices.

Seven countries/territories have multiple current tender codes. The custom destination picker offers only these codes and initially selects the first:

| Code | Ordered codes |
| --- | --- |
| BT | BTN, INR |
| HT | HTG, USD |
| LS | ZAR, LSL |
| NA | NAD, ZAR |
| PA | PAB, USD |
| PS | ILS, JOD |
| ZW | ZWG, USD |

`AQ` (Antarctica) has no national tender currency and an empty list; there is no fabricated default. All other entries have one or more current tender codes. This snapshot correctly uses EUR for Bulgaria and XCG for Curaçao/Sint Maarten. Onboarding selects the first current currency automatically. Custom destinations offer a choice from multi-currency lists; an empty list requires an explicit travel-currency choice. Expense entry continues to accept any of the app's supported currencies.

## Coordinates

Coordinates are representative map points, not boundaries or guaranteed geographic centroids. Google DSPL supplies valid points for 242 of the 250 entries. Seven omitted country codes use an explicitly recorded GeoNames capital point:

| Country/territory | Representative point | GeoNames ID |
| --- | --- | --- |
| AX | Mariehamn | 3041732 |
| BL | Gustavia | 3579132 |
| BQ | Kralendijk | 3513563 |
| CW | Willemstad | 3513090 |
| MF | Marigot | 3578851 |
| SS | Juba | 373303 |
| SX | Philipsburg | 3513392 |

Google's `UM` row contains blank coordinates, and GeoNames lists no capital for this dispersed territory. It uses the pinned GeoNames country-feature representative point `5854968` (`5.875, -162.057`) instead. This is an explicitly documented exception, not a capital or an invented `(0, 0)` point. The generator rejects missing/out-of-range coordinates and `(0, 0)` fallbacks.

The first 22 destination rows preserve the prior `Catalog.swift` names, ordering and coordinates exactly because demo records index those entries. Their stable GeoNames identities are added, but their source coordinates are intentionally overridden by `legacy-destinations.json` through `selection.json`. The prefix is Lisbon, Porto, Seville, Barcelona, Paris, Rome, Tokyo, Kyoto, London, New York, Sydney, Bangkok, Bali, Hanoi, Marrakesh, Athens, Zermatt, Vancouver, Mexico City, Seoul, Dubai and Auckland. Nara uses the friendly display name “Nara” while keeping the source “Nara-shi” alias.

## Selection and aliases

`selection.json` is the explicit, reviewable list of all 500 selected GeoNames IDs, selection reasons and display/coordinate overrides. It is authoritative: generation never silently replaces a destination because population data changed.

The initial selection combined the legacy prefix, the required Taiwan cities (Taipei, Taichung, Kaohsiung and Tainan), all 241 `PPLC` capital features in the current city extract, and a curated travel-city pool. Curated candidates are recorded by country and source ID in `curated-candidates.json`. Selection cycled through countries within regional targets to prevent a few large countries dominating the list. Remaining slots used country-by-country major settlements, not a single global population sort. Three final coverage refinements added Santorini, Naples and Amalfi in place of regional fillers. Every source capital remains included; 230 rows have the explicit capital-selection reason, with the other 11 already included by legacy/Taiwan rules.

The final regional counts, using GeoNames continent membership, are Africa 80, Asia 135, Europe 124, North America 78, South America 44, Oceania 37 and Antarctica 2. Regions and small travel towns are supplemented from official GeoNames RDF because a population-threshold city file cannot represent every useful destination. A country's presence in the country picker does not imply that one of the 500 destinations belongs to it; country-only selection remains available for every entry.

`aliases.json` holds the consciously curated common English, former/common and native-language search terms. Examples include UK/Great Britain, USA, Holland/Nederland, Turkey/Türkiye, Taipei/台北/臺北, Munich/München and New York/NYC. Aliases for ambiguous city names are scoped by country (for example, Penang applies to George Town in Malaysia, never George Town in the Cayman Islands). Country aliases also include CLDR English alternate names and GeoNames ISO alpha-3 names. Destination aliases combine curated terms, source/ascii names, bounded native-script variants and accent/punctuation variants. Unreviewed multilingual Latin aliases from the full GeoNames dump are deliberately not copied wholesale: they can contain historical or neighbouring place names. Search aliases do not change canonical country codes or imply official naming, sovereignty or currency acceptance.

## Destination-local time zones

`DestinationTimeZones.json` has `version`, `countries` and `destinations`. Each of its 500 destination entries contains the existing ID/country/coordinates and an `identifier`; each of its 250 country entries contains `countryCode` and sorted `identifiers`, plus optional `defaultIdentifier` and `defaultSource`. It does not change either original catalogue's bytes, including the 22 demo coordinates.

The [GeoNames dump format](https://download.geonames.org/export/dump/readme.txt) defines zero-based field 17 as the IANA time-zone ID. The importer takes 495 selected IDs from the original pinned `cities15000.zip`. It takes the remaining five from exact pinned country-dump TSV rows: Santorini → `Europe/Athens`, Bali → `Asia/Makassar`, Zermatt → `Europe/Zurich`, Amalfi → `Europe/Rome`, and Queenstown → `Pacific/Auckland`. `geonames-time-zones.json` records each original identifier, source and modification date. No longitude-derived offset or nearest-city lookup is used.

Country choices combine [IANA `zone.tab`](https://data.iana.org/time-zones/tzdb-2026f/zone.tab), which retains familiar country-specific names, with [modern `zone1970.tab`](https://data.iana.org/time-zones/tzdb-2026f/zone1970.tab), whose first column explicitly lists every country overlapping a zone. Names equivalent through pinned `backward` links are deduplicated within a country. This retains distinct zones omitted from the older table: northern Vietnam's `Asia/Bangkok` and southern Vietnam's `Asia/Ho_Chi_Minh` are both scoped choices. GeoNames identifiers must match a country's scoped choice or a verified equivalent alias; generation fails otherwise. Kosovo has no IANA ISO country row, so its `Europe/Belgrade` scope comes from the explicit `territory="XK"` mapping in pinned CLDR `metaZones.xml`.

For a country with one scoped zone, that zone is the representative default. A multi-zone country uses its single GeoNames `PPLC` capital's zone when available; the resource records the capital name and ID. Examples are Washington → `America/New_York`, Canberra → `Australia/Sydney`, Jakarta → `Asia/Jakarta`, and Ottawa → `America/Toronto`. This is a **country representative**, not a precise zone for arbitrary coordinates elsewhere in the country. Catalogue city points retain their own exact source zones, so Los Angeles, Perth, Bali and Vancouver do not inherit those capital defaults.

Antarctica (`AQ`), US Minor Outlying Islands (`UM`) and Palestine (`PS`) expose their scoped choices but have no unambiguous source capital/default; their country representative is absent and the user must choose. Bouvet Island (`BV`) and Heard/McDonald Islands (`HM`) have neither a populated representative nor an IANA scoped country row, so their lists and defaults are empty. No `(0,0)`, UTC or geographically neighbouring zone is invented for these cases.

The Swift `DestinationTimeZones.identifier(countryCode:latitude:longitude:)` API first matches the exact stored catalogue coordinates within the country, then falls back only to the documented country representative. `identifiers(countryCode:)` returns that country's scoped choices. Both omit names unsupported by the device's Foundation time-zone database; an unsupported exact point returns nil rather than silently using a capital or UTC. Apple Maps results supply `MKMapItem.timeZone` directly in the app. Custom/country destinations must make the representative fallback clear and permit an explicit choice. DST rules and date calculations use Foundation's installed IANA data rather than bundled fixed offsets. Tests verify all bundled identifiers are supported on the development platform and distinguish city-specific zones, no-default countries and DST behavior.

`Stop.timeZone` is an additive optional, non-null transport field. The backend validates named zones, persists and returns them, and preserves a saved stop's zone when a legacy `trip.update` omits it for the same stable stop ID. An explicit valid zone may replace it without moving existing civil dates. Receipts still hash the original submitted operation, so omitted-field retries work after eviction and cannot be reused with changed content. Existing revision and referenced-itinerary guards remain active; see [the API contract](../contracts/api.md).

## Reproduction and maintenance

From the repository root, using Python 3.10 or later and only its standard library:

```sh
python3 scripts/generate_destination_catalogue.py
python3 scripts/generate_destination_catalogue.py --check
```

The generator validates source hashes, regenerates all four app resources without network access and prints counts, currency/time-zone exceptions, byte sizes and resource hashes. `--check` compares without writing. Invariants include exactly 250 unique current country codes, 500 unique destination IDs and exact point-to-zone mappings, valid country references, scoped time zones, valid coordinates, supported current currencies, all 22 legacy records, the four Taiwan cities, UK/USA and native Taipei aliases, Munich, São Paulo, Santorini, Naples, Amalfi and Nara.

To audit/reproduce the compact GeoNames input from the original matching ZIP:

```sh
python3 scripts/import_destination_sources.py /path/to/cities15000.zip --check
# Optional full audit of the five supplemental ZIPs, named GR.zip, ID.zip, CH.zip, IT.zip and NZ.zip:
python3 scripts/import_destination_sources.py /path/to/cities15000.zip --supplemental-zip-dir /path/to/country-zips --check
```

Without `--check`, that command rewrites the compact catalogue and time-zone extracts. It rejects a ZIP whose hash differs from the recorded snapshot. Supplemental extraction checks compare the committed TSV rows against the original hashed country archives. Future source updates are intentional data changes: choose current CLDR/IANA releases, refresh the raw sources/RDF and original ZIP hashes, review selected IDs/country codes/currency date transitions/time-zone changes, update `selection.json` and the source hashes, then regenerate. Preserve the 22-entry compatibility prefix unless the dependent demos are migrated in the same change. Review resource diffs and run the app's country/destination/time-zone tests before shipping. Do not package `scripts/destination-data/sources/` into the app; only the four generated resources belong in its bundle.

Current generated SHA-256 values:

| Resource | SHA-256 |
| --- | --- |
| Countries.json | `79a06f6b93b955dffc8eb95b6680ab56e87accd2ceab06e084092331b9cb53b7` |
| Destinations.json | `372f0b52b44abc295d45e7f3c878364c581c5c42248407261d941b505c8968b0` |
| DestinationDataLicenses.txt | `1171961cd85474465813454bad924b0450d0975b2e5a4366610a60c17708b616` |
| DestinationTimeZones.json | `d332b343d1815e03aae4c754d7f21ae9fd3772b9f9f7539c2eb9549e8fde9799` |
