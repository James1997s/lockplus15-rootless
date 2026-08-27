#!/usr/bin/env python3
"""Validate the local LockPlus catalog and its declarative JSON theme files."""
from __future__ import annotations

import json
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1] / 'themes'
CATALOG = ROOT / 'catalog.json'


def fail(message: str) -> None:
    raise SystemExit(message)


def validate_html_fragment(identifier: str, value: str) -> None:
    if len(value) > 8192:
        fail(f'Theme {identifier} contains an HTML fragment that is too large.')
    lower = value.lower()
    blocked = ('<script', '</script', '<iframe', '<object', '<embed', '<link', '<meta', '<style', 'javascript:', 'vbscript:', 'data:text/html', 'expression(', 'url(')
    if any(token in lower for token in blocked) or any(marker in lower for marker in (' onload=', ' onclick=', ' onerror=', ' onmouseover=')):
        fail(f'Theme {identifier} contains unsafe HTML.')


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding='utf-8'))
    entries = catalog.get('themes')
    if not isinstance(entries, list) or not entries:
        fail('Catalog must contain a non-empty themes array.')

    identifiers: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            fail('Catalog contains a non-object entry.')
        identifier = entry.get('id')
        name = entry.get('name')
        location = entry.get('url')
        if not isinstance(identifier, str) or not identifier:
            fail('Theme is missing a safe id.')
        if identifier in identifiers:
            fail(f'Duplicate theme id: {identifier}')
        identifiers.add(identifier)
        if not isinstance(name, str) or not name:
            fail(f'Theme {identifier} has no name.')
        if not isinstance(location, str) or not location.endswith('.json'):
            fail(f'Theme {identifier} has an invalid JSON location.')
        parsed = urlparse(location)
        if parsed.scheme or parsed.netloc or '..' in Path(location).parts:
            fail(f'Theme {identifier} has a non-local or traversal location.')
        path = ROOT / location
        if not path.is_file():
            fail(f'Theme file missing: {location}')
        theme = json.loads(path.read_text(encoding='utf-8'))
        if theme.get('format') == 'folder':
            files = theme.get('files')
            base_path = theme.get('basePath')
            if not isinstance(base_path, str) or not base_path or base_path.startswith('/') or '://' in base_path or '..' in Path(base_path).parts or theme.get('entry') != 'LockBackground.html' or not isinstance(files, list) or not files or len(files) > 64:
                fail(f'Theme {identifier} has an invalid folder manifest.')
            paths = set()
            for item in files:
                if not isinstance(item, dict) or not isinstance(item.get('path'), str) or item['path'] in paths or item['path'].startswith('/') or '..' in Path(item['path']).parts:
                    fail(f'Theme {identifier} has an unsafe folder path.')
                paths.add(item['path'])
                if not isinstance(item.get('sha256'), str) or len(item['sha256']) != 64:
                    fail(f'Theme {identifier} has an invalid folder hash.')
                local = path.parent / 'folder-themes' / identifier / item['path']
                if not local.is_file() or __import__('hashlib').sha256(local.read_bytes()).hexdigest() != item['sha256'].lower():
                    fail(f'Theme {identifier} folder hash mismatch: {item["path"]}.')
            if 'LockBackground.html' not in paths:
                fail(f'Theme {identifier} is missing LockBackground.html.')
            continue
        elements = theme.get('placedElements')
        if not isinstance(elements, dict) or not elements:
            fail(f'Theme {identifier} lacks placedElements.')
        for key, properties in elements.items():
            if not isinstance(key, str) or not isinstance(properties, dict):
                fail(f'Theme {identifier} has an invalid element.')
            for property_name, property_value in properties.items():
                if not isinstance(property_name, str) or not isinstance(property_value, str):
                    fail(f'Theme {identifier} has a non-string style property.')
                if property_value.lower().startswith(('javascript:', 'data:text/html')):
                    fail(f'Theme {identifier} has a blocked URI.')
                if properties.get('type') == 'html' and property_name == 'innerHTML':
                    validate_html_fragment(identifier, property_value)

    print(f'Validated {len(entries)} catalog entries and theme files.')


if __name__ == '__main__':
    main()
