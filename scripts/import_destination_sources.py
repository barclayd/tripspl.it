#!/usr/bin/env python3
"""Reproduce the compact GeoNames input from the recorded original dump and pinned RDF."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'scripts' / 'destination-data'
SOURCES = DATA / 'sources'
NS = {'gn': 'http://www.geonames.org/ontology#',
      'geo': 'http://www.w3.org/2003/01/geo/wgs84_pos#',
      'rdf': 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cities_zip', type=Path,
                        help='Original cities15000.zip matching upstream.json SHA-256.')
    parser.add_argument('--check', action='store_true', help='Compare without rewriting the compact input.')
    parser.add_argument('--supplemental-zip-dir', type=Path,
                        help='Optionally verify the five original country ZIPs named <country>.zip.')
    args = parser.parse_args()
    upstream = json.loads((DATA / 'upstream.json').read_text())
    manifest = json.loads((DATA / 'selection.json').read_text())
    digest = hashlib.sha256(args.cities_zip.read_bytes()).hexdigest()
    if digest != upstream['geonamesCities15000Sha256']:
        raise ValueError('Dump differs from the recorded snapshot; review/version a source update explicitly.')
    selected = {entry['geonameId'] for entry in manifest['destinations']}
    selected.update(manifest['countryCentreFallbacks'].values())
    selected.update(manifest.get('countryFeatureFallbacks', {}).values())
    records = {}
    time_zones = {}
    with zipfile.ZipFile(args.cities_zip) as archive:
        for line in archive.read('cities15000.txt').decode('utf-8').splitlines():
            fields = line.split('\t')
            if fields[0] not in selected:
                continue
            records[fields[0]] = dict(
                geonameId=fields[0], name=fields[1], asciiName=fields[2],
                alternateNames=fields[3].split(','), latitude=float(fields[4]),
                longitude=float(fields[5]), featureCode=fields[7], countryCode=fields[8],
                population=int(fields[14]), modificationDate=fields[18])
            time_zones[fields[0]] = dict(geonameId=fields[0], countryCode=fields[8],
                                       identifier=fields[17], modificationDate=fields[18],
                                       source='cities15000')
    for path in sorted(SOURCES.glob('geonames-*.rdf')):
        gid = path.stem.removeprefix('geonames-')
        if gid not in selected:
            continue
        feature = ET.parse(path).getroot().find('gn:Feature', NS)
        if feature is None:
            raise ValueError(f'Missing GeoNames feature in {path}')
        country = feature.findtext('gn:countryCode', namespaces=NS)
        name = feature.findtext('gn:name', namespaces=NS)
        feature_code = feature.find('gn:featureCode', NS).attrib['{' + NS['rdf'] + '}resource']
        records[gid] = dict(
            geonameId=gid, name=name, asciiName=name,
            alternateNames=[] if country == 'UM' else [node.text for node in feature.findall('gn:alternateName', NS) if node.text],
            latitude=float(feature.findtext('geo:lat', namespaces=NS)),
            longitude=float(feature.findtext('geo:long', namespaces=NS)),
            featureCode=feature_code.split('#')[-1].split('.')[-1], countryCode=country,
            population=0, retrievedOn=upstream['geonamesRetrievedOn'])
    if set(records) != selected:
        raise ValueError(f'Selected IDs missing from source: {sorted(selected - records.keys())}')
    supplemental = (SOURCES / 'geonames-supplemental-time-zones.tsv').read_text(encoding='utf-8')
    supplemental_ids = set()
    for line in supplemental.splitlines():
        fields = line.split('\t')
        if fields[0] not in selected or fields[0] in time_zones:
            raise ValueError(f'Unexpected supplemental time-zone record: {fields[0]}')
        supplemental_ids.add(fields[0])
        time_zones[fields[0]] = dict(geonameId=fields[0], countryCode=fields[8],
                                   identifier=fields[17], modificationDate=fields[18],
                                   source='country:' + fields[8])
    if args.supplemental_zip_dir:
        original_lines = []
        for country, source in upstream['geonamesSupplementalTimeZoneDumps'].items():
            archive_path = args.supplemental_zip_dir / (country + '.zip')
            if hashlib.sha256(archive_path.read_bytes()).hexdigest() != source['sha256']:
                raise ValueError(f'Supplemental dump hash mismatch: {country}')
            with zipfile.ZipFile(archive_path) as archive:
                original_lines += [line for line in archive.read(country + '.txt').decode('utf-8').splitlines()
                                   if line.split('\t', 1)[0] in supplemental_ids]
        reconstructed = '\n'.join(sorted(original_lines, key=lambda line: int(line.split('\t')[0]))) + '\n'
        if reconstructed != supplemental:
            raise ValueError('Supplemental time-zone rows differ from original country dumps')
    destination_ids = {entry['geonameId'] for entry in manifest['destinations']}
    if set(time_zones) != destination_ids or any(not row['identifier'] for row in time_zones.values()):
        raise ValueError('Every selected destination must have an explicit GeoNames time zone')
    content = json.dumps([records[key] for key in sorted(records, key=int)], ensure_ascii=False, indent=2) + '\n'
    zone_content = json.dumps([time_zones[key] for key in sorted(time_zones, key=int)],
                              ensure_ascii=False, indent=2) + '\n'
    for name, value in [('geonames-selected.json', content), ('geonames-time-zones.json', zone_content)]:
        output = SOURCES / name
        if args.check:
            if output.read_text(encoding='utf-8') != value:
                raise ValueError(f'Compact source extract differs from reconstruction: {name}')
        else:
            output.write_text(value, encoding='utf-8')
    print(f'{len(records)} selected/source-reference records verified; SHA-256 {hashlib.sha256(content.encode()).hexdigest()}')
    print(f'{len(time_zones)} destination time zones verified; SHA-256 {hashlib.sha256(zone_content.encode()).hexdigest()}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
