#!/usr/bin/env python3
"""Audit every LockPlus catalog theme against the native UIKit renderer contract."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1] / 'themes'
CATALOG = ROOT / 'catalog.json'
SUPPORTED_TYPES = {'clock', 'date', 'word-clock', 'text', 'wallpaper', 'panel', 'blob', 'particle', 'ring', 'image', 'widget', 'overlay', 'ecg-time', 'brushstroke-time'}
SUPPORTED_PROPERTIES = {
    'type', 'position', 'left', 'top', 'transform', 'color', 'font-family',
    'font-size', 'font-weight', 'letter-spacing', 'text-shadow', 'z-index',
    'innerHTML', 'background-color', 'border', 'border-radius', 'box-shadow',
    'padding', 'width', 'height', 'gradient', 'animation', 'animation-duration',
    'x', 'size', 'opacity', 'motion', 'motion-distance', 'motion-duration',
    'diameter', 'stroke-width', 'arc-start', 'arc-length', 'dash', 'rotation-duration', 'rotation-direction',
    'asset-id', 'image-role', 'time-format', 'uppercase', 'text-texture-asset-id', 'cookie-glyph-atlas-asset-id', 'cookie-letter-glyph-atlas-asset-id', 'cookie-number-glyph-atlas-asset-id', 'grid-color', 'brush-asset-id', 'painting-asset-ids',
}
REQUIRED_BY_TYPE = {
    'clock': {'top', 'color', 'font-size'},
    'date': {'top', 'color', 'font-size'},
    'word-clock': {'top', 'color', 'font-size'},
    'text': {'top', 'color', 'font-size'},
    'panel': {'top', 'background-color', 'innerHTML'},
    'wallpaper': {'gradient'},
    'blob': {'top', 'color', 'size', 'x'},
    'particle': {'top', 'color', 'size', 'x'},
    'ring': {'top', 'color', 'diameter', 'stroke-width'},
    'image': {'asset-id'},
    'ecg-time': {'top', 'color', 'grid-color', 'width', 'height', 'stroke-width'},
    'brushstroke-time': {'top', 'color', 'brush-asset-id', 'painting-asset-ids', 'width', 'height', 'stroke-width'},
    'widget': {'top', 'background-color', 'innerHTML'},
    'overlay': {'top', 'background-color', 'innerHTML'},
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
        assets = theme.get('assets', [])
        if not isinstance(assets, list) or len(assets) > 6:
            errors.append(f'{identifier}: invalid assets collection.')
        else:
            asset_ids: set[str] = set()
            for asset in assets:
                if not isinstance(asset, dict):
                    errors.append(f'{identifier}: invalid asset record.')
                    continue
                asset_id = asset.get('id')
                asset_url = asset.get('url')
                asset_hash = asset.get('sha256')
                if not isinstance(asset_id, str) or not asset_id or len(asset_id) > 48 or not all(char.isalnum() or char in '_-' for char in asset_id):
                    errors.append(f'{identifier}: invalid asset id {asset_id!r}.')
                elif asset_id in asset_ids:
                    errors.append(f'{identifier}: duplicate asset id {asset_id}.')
                else:
                    asset_ids.add(asset_id)
                if not isinstance(asset_url, str) or Path(asset_url).suffix.lower() not in {'.jpg', '.jpeg', '.png', '.gif'} or asset_url.startswith('/') or '..' in Path(asset_url).parts:
                    errors.append(f'{identifier}: unsafe asset URL {asset_url!r}.')
                    continue
                asset_path = ROOT / asset_url
                if not asset_path.is_file():
                    errors.append(f'{identifier}: missing asset {asset_url}.')
                elif not isinstance(asset_hash, str) or len(asset_hash) != 64 or hashlib.sha256(asset_path.read_bytes()).hexdigest() != asset_hash.lower():
                    errors.append(f'{identifier}: asset SHA-256 mismatch for {asset_url}.')

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
            unsupported = set(properties) - SUPPORTED_PROPERTIES
            if unsupported:
                errors.append(f'{identifier}/{element_id}: unsupported renderer properties {sorted(unsupported)}.')
            if properties.get('position') not in {None, 'absolute'}:
                errors.append(f'{identifier}/{element_id}: unsupported position mode.')
            if properties.get('left') not in {None, '50%'}:
                errors.append(f'{identifier}/{element_id}: only centered left positioning is supported.')
            if properties.get('transform') not in {None, 'translateX(-50%)'}:
                errors.append(f'{identifier}/{element_id}: unsupported transform.')
            if 'javascript:' in ' '.join(str(value).lower() for value in properties.values()):
                errors.append(f'{identifier}/{element_id}: unsafe URI value.')
            if element_type == 'image' and properties.get('asset-id') not in asset_ids:
                errors.append(f'{identifier}/{element_id}: image asset-id must reference a declared asset.')
            if element_type == 'brushstroke-time' and properties.get('brush-asset-id') not in asset_ids:
                errors.append(f'{identifier}/{element_id}: brush-asset-id must reference a declared asset.')
            if element_type == 'brushstroke-time':
                painting_ids = [asset_id.strip() for asset_id in properties.get('painting-asset-ids', '').split(',') if asset_id.strip()]
                if len(painting_ids) > 2 or any(asset_id not in asset_ids for asset_id in painting_ids):
                    errors.append(f'{identifier}/{element_id}: painting-asset-ids must reference at most two declared assets.')
        theme_count += 1

    if errors:
        fail(errors)
    print(f'Native compatibility verified: {theme_count} themes, {element_count} elements, {len(identifiers)} safe ids.')


if __name__ == '__main__':
    main()
