#!/usr/bin/env python3
"""Audit every LockPlus catalog theme against the native UIKit renderer contract."""
from __future__ import annotations

import json
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1] / 'themes'
CATALOG = ROOT / 'catalog.json'
SUPPORTED_TYPES = {'clock', 'date', 'text'}
REQUIRED_BY_TYPE = {
    'clock': {'top', 'color', 'font-size'},
    'date': {'top', 'color', 'font-size'},
    'text': {'top', 'color', 'font-size'},
}


def fail(messages: list[str]) -> None:
    for message in messages:
        print(f'ERROR: {message}')
    raise SystemExit(1)


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding='utf-8'))
    records = catalog.get('themes')
    errors: list[str] = []
    if not isinstance(records, list):
        fail(['Catalog does not contain a themes array.'])

    identifiers: set[str] = set()
    theme_count = 0
    element_count = 0
    for record in records:
        if not isinstance(record, dict):
            errors.append('Non-object catalog record.')
            continue
        identifier = record.get('id')
        location = record.get('url')
        if not isinstance(identifier, str) or not identifier or len(identifier) > 48:
            errors.append(f'Invalid runtime theme id: {identifier!r}')
            continue
        if identifier in identifiers:
            errors.append(f'Duplicate runtime theme id: {identifier}')
        identifiers.add(identifier)
        if not isinstance(location, str) or not location.endswith('.json'):
            errors.append(f'{identifier}: invalid JSON location.')
            continue
        parsed = urlparse(location)
        if parsed.scheme or parsed.netloc or location.startswith('/') or '..' in Path(location).parts:
            errors.append(f'{identifier}: unsafe relative URL {location!r}.')
            continue
        theme_path = ROOT / location
        if not theme_path.is_file():
            errors.append(f'{identifier}: missing theme file {location}.')
            continue
        theme = json.loads(theme_path.read_text(encoding='utf-8'))
        placed = theme.get('placedElements')
        if not isinstance(placed, dict) or not placed or len(placed) > 128:
            errors.append(f'{identifier}: invalid placedElements collection.')
            continue
        for element_id, properties in placed.items():
            element_count += 1
            if not isinstance(element_id, str) or not isinstance(properties, dict):
                errors.append(f'{identifier}: invalid element record.')
                continue
            element_type = properties.get('type', 'text')
            if element_type not in SUPPORTED_TYPES:
                errors.append(f'{identifier}/{element_id}: unsupported native type {element_type!r}.')
            missing = REQUIRED_BY_TYPE.get(element_type, set()) - set(properties)
            if missing:
                errors.append(f'{identifier}/{element_id}: missing required renderer keys {sorted(missing)}.')
            if any(not isinstance(key, str) or not isinstance(value, str) for key, value in properties.items()):
                errors.append(f'{identifier}/{element_id}: all properties must be strings.')
            if 'javascript:' in ' '.join(str(value).lower() for value in properties.values()):
                errors.append(f'{identifier}/{element_id}: unsafe URI value.')
        theme_count += 1

    if errors:
        fail(errors)
    print(f'Native compatibility verified: {theme_count} themes, {element_count} elements, {len(identifiers)} safe ids.')


if __name__ == '__main__':
    main()
