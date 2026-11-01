#!/usr/bin/env python3
"""Rebuild TripSplit's bundled country/destination catalogue without network access."""
from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import unicodedata
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'scripts' / 'destination-data'
SOURCES = DATA / 'sources'
OUTPUT = ROOT / 'Packages' / 'TripSplitDomain' / 'Sources' / 'TripSplitDomain' / 'Resources'


def read_json(path: Path):
    return json.loads(path.read_text(encoding='utf-8'))


def ascii_alias(value: str) -> str:
    return ''.join(c for c in unicodedata.normalize('NFKD', value)
                   if not unicodedata.combining(c))


def unique_aliases(name: str, candidates: list[str], maximum: int) -> list[str]:
    seen = {name.casefold()}
    aliases = []
    for candidate in candidates:
        candidate = re.sub(r'\s+', ' ', candidate).strip()
        if not candidate or len(candidate) > 80 or candidate.casefold() in seen:
            continue
        if any(unicodedata.category(c).startswith('C') for c in candidate):
            continue
        seen.add(candidate.casefold())
        aliases.append(candidate)
        if len(aliases) == maximum:
            break
    return aliases


def native_aliases(record: dict) -> list[str]:
    scripts = {
        'JP': ['CJK', 'HIRAGANA', 'KATAKANA'], 'TW': ['CJK'], 'CN': ['CJK'],
        'HK': ['CJK'], 'MO': ['CJK'], 'KR': ['HANGUL'], 'KP': ['HANGUL'],
        'TH': ['THAI'], 'LA': ['LAO'], 'KH': ['KHMER'], 'MM': ['MYANMAR'],
        'GR': ['GREEK'], 'CY': ['GREEK'], 'RU': ['CYRILLIC'],
        'UA': ['CYRILLIC'], 'BY': ['CYRILLIC'], 'BG': ['CYRILLIC'],
        'RS': ['CYRILLIC'], 'MK': ['CYRILLIC'], 'MN': ['CYRILLIC'],
        'AM': ['ARMENIAN'], 'GE': ['GEORGIAN'], 'IL': ['HEBREW', 'ARABIC'],
        'IR': ['ARABIC'], 'AE': ['ARABIC'], 'SA': ['ARABIC'], 'OM': ['ARABIC'],
        'QA': ['ARABIC'], 'BH': ['ARABIC'], 'KW': ['ARABIC'], 'JO': ['ARABIC'],
        'LB': ['ARABIC'], 'IQ': ['ARABIC'], 'SY': ['ARABIC'], 'YE': ['ARABIC'],
        'EG': ['ARABIC'], 'MA': ['ARABIC'], 'TN': ['ARABIC'], 'DZ': ['ARABIC'],
        'LY': ['ARABIC'], 'SD': ['ARABIC'], 'PS': ['ARABIC'],
        'IN': ['DEVANAGARI', 'BENGALI', 'TAMIL', 'KANNADA', 'MALAYALAM'],
        'NP': ['DEVANAGARI'], 'BD': ['BENGALI'], 'LK': ['SINHALA', 'TAMIL'],
        'ET': ['ETHIOPIC'], 'ER': ['ETHIOPIC'], 'PK': ['ARABIC'],
    }.get(record['countryCode'], [])
    result = []
    for script in scripts:
        matches = [alias for alias in record['alternateNames']
                   if 2 <= len(alias) <= 60 and any(
                       script in unicodedata.name(c, '') for c in alias)]
        result.extend(sorted(set(matches), key=lambda value: (len(value), value))[:2])
    return result[:4]


def currency_active(currency: ET.Element, as_of: str) -> bool:
    # CLDR's absent tender attribute defaults to true. Date strings are ISO dates.
    return (currency.get('tender', 'true') == 'true'
            and currency.get('from', '0001-01-01') <= as_of
            and currency.get('to', '9999-12-31') >= as_of)


def destination_time_zones(countries: list[dict], destinations: list[dict], records: dict) -> dict:
    links = {}
    for line in (SOURCES / 'iana-backward').read_text(encoding='utf-8').splitlines():
        fields = line.split('#', 1)[0].split()
        if fields and fields[0] == 'Link':
            links[fields[2]] = fields[1]

    def canonical(identifier: str) -> str:
        seen = set()
        while identifier in links:
            if identifier in seen:
                raise ValueError('IANA link cycle')
            seen.add(identifier)
            identifier = links[identifier]
        return identifier

    zones = collections.defaultdict(list)
    # Keep familiar country-specific names, supplementing with all modern cross-country
    # zones (for example, northern Vietnam uses Asia/Bangkok in zone1970.tab).
    for filename in ['iana-zone.tab', 'iana-zone1970.tab']:
        for line in (SOURCES / filename).read_text(encoding='utf-8').splitlines():
            if not line or line.startswith('#'):
                continue
            fields = line.split('\t')
            for country in fields[0].split(','):
                if not any(canonical(zone) == canonical(fields[2]) for zone in zones[country]):
                    zones[country].append(fields[2])

    cldr = ET.parse(SOURCES / 'cldr-metaZones.xml').getroot()
    for mapping in cldr.findall('.//mapZone'):
        country = mapping.get('territory')
        if country == 'XK':
            # Kosovo has a current GeoNames/CLDR code but no ISO row in IANA's tables.
            zones[country] += [zone for zone in mapping.attrib['type'].split() if zone not in zones[country]]

    source = {row['geonameId']: row for row in read_json(SOURCES / 'geonames-time-zones.json')}

    def scoped(identifier: str, country: str) -> str:
        if identifier in zones[country]:
            return identifier
        matches = [zone for zone in zones[country] if canonical(zone) == canonical(identifier)]
        if not matches:
            raise ValueError(f'GeoNames zone {identifier} is outside the IANA/CLDR scope for {country}')
        return matches[0]

    country_rows = []
    for country in countries:
        code = country['code']
        row = dict(countryCode=code, identifiers=sorted(zones[code]))
        capitals = [record for record in records.values()
                    if record['countryCode'] == code and record['featureCode'] == 'PPLC'
                    and record['geonameId'] in source]
        if len(zones[code]) == 1:
            row['defaultIdentifier'] = zones[code][0]
            row['defaultSource'] = 'Only scoped IANA/CLDR zone'
        elif len(capitals) == 1:
            capital = capitals[0]
            row['defaultIdentifier'] = scoped(source[capital['geonameId']]['identifier'], code)
            row['defaultSource'] = f"GeoNames capital: {capital['name']} ({capital['geonameId']})"
        # With no unambiguous capital/single zone, leave the representative unset.
        # AQ, UM and PS require a choice; uninhabited BV/HM have no scoped zones.
        country_rows.append(row)

    destination_rows = []
    for destination in destinations:
        gid = destination['id'].removeprefix('geonames-')
        raw = source[gid]
        assert raw['countryCode'] == destination['countryCode']
        destination_rows.append(dict(id=destination['id'], countryCode=destination['countryCode'],
                                     latitude=destination['latitude'], longitude=destination['longitude'],
                                     identifier=scoped(raw['identifier'], destination['countryCode'])))
    assert len(source) == len(destination_rows) == 500
    assert len({(row['countryCode'], row['latitude'], row['longitude']) for row in destination_rows}) == 500
    return dict(version=(SOURCES / 'iana-version').read_text().strip(),
                countries=country_rows, destinations=destination_rows)


def generate() -> tuple[dict[str, str], dict]:
    manifest = read_json(DATA / 'selection.json')
    aliases = read_json(DATA / 'aliases.json')
    supported = set(read_json(ROOT / 'contracts' / 'currencies.json')['minorUnits'])
    source_records = read_json(SOURCES / 'geonames-selected.json')
    records = {record['geonameId']: record for record in source_records}
    if len(records) != len(source_records):
        raise ValueError('Duplicate GeoNames source ID')

    country_info = {}
    for line in (SOURCES / 'geonames-countryInfo.txt').read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split('\t')
        if fields[0] not in {'AN', 'CS'}:
            country_info[fields[0]] = fields
    centres = {row['country']: row for row in csv.DictReader(
        io.StringIO((SOURCES / 'country-centres.csv').read_text(encoding='utf-8')))}
    locale = ET.parse(SOURCES / 'cldr-en.xml').getroot()
    territories = locale.findall('./localeDisplayNames/territories/territory')
    default_names = {node.attrib['type']: node.text for node in territories
                     if 'alt' not in node.attrib}
    currency_data = ET.parse(SOURCES / 'cldr-supplementalData.xml').getroot()
    currencies = {}
    unsupported_active = {}
    for region in currency_data.findall('./currencyData/region'):
        code = region.attrib['iso3166']
        values = [node.attrib['iso4217'] for node in region.findall('currency')
                  if currency_active(node, manifest['asOf'])]
        currencies[code] = list(dict.fromkeys(value for value in values if value in supported))
        if code in country_info and any(value not in supported for value in values):
            unsupported_active[code] = [value for value in values if value not in supported]

    countries = []
    for code, fields in sorted(country_info.items()):
        name = default_names.get(code) or fields[4].strip()
        if code in centres and centres[code]['latitude'] and centres[code]['longitude']:
            latitude = float(centres[code]['latitude'])
            longitude = float(centres[code]['longitude'])
        elif code in manifest.get('countryFeatureFallbacks', {}):
            source = records[manifest['countryFeatureFallbacks'][code]]
            assert source['countryCode'] == code and source['featureCode'] in {'PCLD', 'PCL', 'PCLF'}
            latitude, longitude = source['latitude'], source['longitude']
        else:
            source = records[manifest['countryCentreFallbacks'][code]]
            if source['countryCode'] != code or source['featureCode'] != 'PPLC':
                raise ValueError(f'Invalid representative capital point for {code}')
            latitude, longitude = source['latitude'], source['longitude']
        candidates = [fields[1], fields[4].strip(), ascii_alias(name)]
        candidates += aliases['countries'].get(code, [])
        candidates += [node.text for node in territories
                       if node.attrib['type'] == code and node.text]
        countries.append(dict(code=code, name=name, currencies=currencies.get(code, []),
                              latitude=latitude, longitude=longitude,
                              aliases=unique_aliases(name, candidates, 16)))

    destinations = []
    for selection in manifest['destinations']:
        record = records[selection['geonameId']]
        override = selection.get('overrides', {})
        name = override.get('name', record['name'])
        candidates = list(aliases['destinations'].get(name, []))
        candidates += aliases.get('scopedDestinations', {}).get(record['countryCode'] + ':' + name, [])
        candidates += [record['name'], record['asciiName'], ascii_alias(name)]
        candidates += native_aliases(record)
        # Unreviewed source alternates can include historical/neighbouring place names.
        # Import only accent/punctuation variants of the actual display/source names.
        normalized = lambda value: ''.join(c for c in ascii_alias(value).casefold() if c.isalnum())
        spellings = {normalized(name), normalized(record['name']), normalized(record['asciiName'])}
        candidates += [value for value in record['alternateNames']
                       if normalized(value) in spellings]
        destinations.append(dict(id='geonames-' + record['geonameId'], name=name,
                                 countryCode=record['countryCode'],
                                 latitude=override.get('latitude', record['latitude']),
                                 longitude=override.get('longitude', record['longitude']),
                                 aliases=unique_aliases(name, candidates, 12)))

    # Structural and product invariants are part of the import, not optional postprocessing.
    assert len(countries) == 250 and len({row['code'] for row in countries}) == 250
    assert 'XK' in country_info and not {'AN', 'CS'} & country_info.keys()
    assert len(destinations) == manifest['count'] == 500
    assert len({row['id'] for row in destinations}) == 500
    for row in countries + destinations:
        assert -90 <= row['latitude'] <= 90 and -180 <= row['longitude'] <= 180
        assert (row['latitude'], row['longitude']) != (0, 0)
    for row in destinations:
        assert row['countryCode'] in country_info
    for row in countries:
        assert set(row['currencies']) <= supported
    for index, expected in enumerate(read_json(DATA / 'legacy-destinations.json')):
        assert all(destinations[index][key] == value for key, value in expected.items())
    for name in ['Taipei', 'Taichung', 'Kaohsiung', 'Tainan']:
        assert any(row['name'] == name and row['countryCode'] == 'TW' for row in destinations)
    by_country = {row['code']: row for row in countries}
    assert by_country['PA']['currencies'] == ['PAB', 'USD']
    assert by_country['BT']['currencies'] == ['BTN', 'INR']
    assert by_country['AQ']['currencies'] == []
    assert 'UK' in by_country['GB']['aliases'] and 'USA' in by_country['US']['aliases']
    taipei = next(row for row in destinations if row['name'] == 'Taipei')
    assert {'台北', '臺北'} <= set(taipei['aliases'])
    munich = next(row for row in destinations if row['name'] == 'Munich')
    assert 'München' in munich['aliases']
    assert any(row['name'] == 'São Paulo' for row in destinations)
    assert {'Santorini', 'Naples', 'Amalfi', 'Nara'} <= {row['name'] for row in destinations}
    assert all('Penang' not in row['aliases'] for row in destinations if row['countryCode'] != 'MY')

    licences = '\n'.join([
        'TripSplit offline destination data — attribution and licences',
        'Catalogue snapshot: 2026-11-01. This is a curated search catalogue, not a tourism ranking.',
        '', 'GEONAMES',
        'Geographical names, country/territory codes, destination coordinates, time-zone identifiers and source aliases © GeoNames contributors.',
        'Source: https://www.geonames.org/ — https://download.geonames.org/export/dump/',
        'Licence: Creative Commons Attribution 4.0 International (CC BY 4.0).',
        'Changes by TripSplit: selection of 500 destinations, bounded/curated search aliases, English display names,',
        'country representative-point fallbacks, and preservation of 22 pre-existing demo coordinates.',
        'No endorsement by GeoNames is implied. Full CC BY 4.0 licence follows.',
        '', (SOURCES / 'cc-by-4.0.txt').read_text(encoding='utf-8'),
        '', 'GOOGLE DATASET PUBLISHING LANGUAGE (DSPL) — COUNTRY REPRESENTATIVE COORDINATES',
        'Source: https://github.com/google/dspl/blob/master/samples/google/canonical/countries.csv',
        'The coordinate data is redistributed under the following BSD licence:',
        '', (SOURCES / 'dspl-license.txt').read_text(encoding='utf-8'),
        '', 'UNICODE CLDR 49 — ENGLISH TERRITORY NAMES AND CURRENT TENDER CURRENCIES',
        'Source: https://github.com/unicode-org/cldr/tree/96e54b273d2da4ec6fbad350ba19ff23fa24a588',
        'Currency records are filtered for 2026-11-01, tender=true, and TripSplit-supported ISO codes.',
        'CLDR and Google source order/coordinates are preserved except as documented in docs/destination-data.md.',
        '', (SOURCES / 'unicode-license.txt').read_text(encoding='utf-8'),
        '', 'IANA TIME ZONE DATABASE 2026f — COUNTRY TIME-ZONE SCOPE AND ALIASES',
        'Source: https://data.iana.org/time-zones/tzdb-2026f/',
        'Country choices combine zone.tab and zone1970.tab, with equivalent backward links deduplicated.',
        'These source tables and backward links are in the public domain. The tzdb licence follows.',
        '', (SOURCES / 'iana-LICENSE').read_text(encoding='utf-8'),
    ])
    time_zones = destination_time_zones(countries, destinations, records)
    files = {
        'Countries.json': json.dumps(countries, ensure_ascii=False, indent=2) + '\n',
        'Destinations.json': json.dumps(destinations, ensure_ascii=False, indent=2) + '\n',
        'DestinationDataLicenses.txt': licences.rstrip() + '\n',
        'DestinationTimeZones.json': json.dumps(time_zones, ensure_ascii=False, indent=2) + '\n',
    }
    summary = {
        'countriesAndTerritories': len(countries), 'destinations': len(destinations),
        'countriesWithMultipleCurrencies': {row['code']: row['currencies'] for row in countries
                                           if len(row['currencies']) > 1},
        'countriesWithoutSupportedNationalTender': [row['code'] for row in countries if not row['currencies']],
        'unsupportedActiveCLDRCodes': unsupported_active,
        'timeZoneVersion': time_zones['version'],
        'countriesWithoutTimeZoneDefault': [row['countryCode'] for row in time_zones['countries']
                                           if 'defaultIdentifier' not in row],
        'selectionReasons': dict(collections.Counter(row['reason'] for row in manifest['destinations'])),
        'resourceBytes': {name: len(content.encode('utf-8')) for name, content in files.items()},
        'resourceSHA256': {name: hashlib.sha256(content.encode('utf-8')).hexdigest()
                           for name, content in files.items()},
    }
    return files, summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify checked-in outputs without writing.')
    args = parser.parse_args()
    hashes_path = DATA / 'source-hashes.json'
    if hashes_path.exists():
        for relative, expected in read_json(hashes_path).items():
            actual = hashlib.sha256((DATA / relative).read_bytes()).hexdigest()
            if actual != expected:
                raise ValueError(f'Source hash mismatch: {relative}')
    files, summary = generate()
    if args.check:
        for name, content in files.items():
            if (OUTPUT / name).read_text(encoding='utf-8') != content:
                raise ValueError(f'Generated resource differs: {name}')
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for name, content in files.items():
            (OUTPUT / name).write_text(content, encoding='utf-8')
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
