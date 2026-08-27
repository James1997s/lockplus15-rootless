#!/usr/bin/env python3
"""Copy all current catalog themes into SpecialLock's local rootless package payload."""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
THEMES = PROJECT / 'themes'
CATALOG = THEMES / 'catalog.json'
DESTINATION = PROJECT / 'layout' / 'Library' / 'SpecialLock' / 'Themes'


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_relative(value: str) -> Path:
    path = Path(value)
    if not value or path.is_absolute() or '..' in path.parts:
        raise ValueError(f'unsafe relative path: {value!r}')
    return path


def copy_file(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    destination.chmod(0o644)


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding='utf-8'))
    records = catalog.get('themes')
    if not isinstance(records, list) or not records:
        raise SystemExit('catalog.json does not define a non-empty themes array')

    if DESTINATION.exists():
        shutil.rmtree(DESTINATION)
    DESTINATION.mkdir(parents=True)
    copy_file(CATALOG, DESTINATION / 'catalog.json')

    theme_count = 0
    folder_count = 0
    asset_count = 0
    for record in records:
        if not isinstance(record, dict):
            raise SystemExit('catalog record is not an object')
        theme_id = record.get('id')
        theme_location = record.get('url')
        if not isinstance(theme_id, str) or not theme_id or not isinstance(theme_location, str):
            raise SystemExit('catalog record is missing an id or url')
        source_manifest = THEMES / safe_relative(theme_location)
        if not source_manifest.is_file():
            raise SystemExit(f'missing catalog manifest: {theme_location}')
        manifest = json.loads(source_manifest.read_text(encoding='utf-8'))
        if manifest.get('id') not in {None, theme_id}:
            raise SystemExit(f'{theme_location}: manifest id does not match catalog id')

        # Keep the catalog path for Settings and also copy a predictable root
        # manifest path for SpringBoard's selected-theme resolver.
        copy_file(source_manifest, DESTINATION / safe_relative(theme_location))
        copy_file(source_manifest, DESTINATION / f'{theme_id}.json')
        theme_count += 1

        if manifest.get('format') == 'folder':
            base_path = manifest.get('basePath')
            files = manifest.get('files')
            entry = manifest.get('entry')
            if not isinstance(base_path, str) or not isinstance(files, list) or entry != 'LockBackground.html':
                raise SystemExit(f'{theme_location}: invalid folder manifest')
            folder_root = THEMES / safe_relative(base_path)
            has_entry = False
            for file_record in files:
                if not isinstance(file_record, dict):
                    raise SystemExit(f'{theme_location}: invalid folder file record')
                relative_path = file_record.get('path')
                expected_hash = file_record.get('sha256')
                if not isinstance(relative_path, str) or not isinstance(expected_hash, str):
                    raise SystemExit(f'{theme_location}: folder file record missing path or hash')
                source_file = folder_root / safe_relative(relative_path)
                if not source_file.is_file() or sha256(source_file) != expected_hash.lower():
                    raise SystemExit(f'{theme_location}: folder file hash mismatch for {relative_path}')
                copy_file(source_file, DESTINATION / 'Folders' / theme_id / safe_relative(relative_path))
                asset_count += 1
                has_entry = has_entry or relative_path == entry
            if not has_entry:
                raise SystemExit(f'{theme_location}: folder manifest lacks LockBackground.html')
            folder_count += 1
            continue

        assets = manifest.get('assets', [])
        if not isinstance(assets, list):
            raise SystemExit(f'{theme_location}: invalid native assets')
        for asset in assets:
            if not isinstance(asset, dict):
                raise SystemExit(f'{theme_location}: invalid asset record')
            asset_id = asset.get('id')
            asset_location = asset.get('url')
            expected_hash = asset.get('sha256')
            if not isinstance(asset_id, str) or not isinstance(asset_location, str) or not isinstance(expected_hash, str):
                raise SystemExit(f'{theme_location}: asset record missing id, url, or checksum')
            source_asset = THEMES / safe_relative(asset_location)
            if not source_asset.is_file() or sha256(source_asset) != expected_hash.lower():
                raise SystemExit(f'{theme_location}: asset hash mismatch for {asset_location}')
            copy_file(source_asset, DESTINATION / 'Assets' / theme_id / asset_id)
            asset_count += 1

    for directory in [path for path in DESTINATION.rglob('*') if path.is_dir()]:
        directory.chmod(0o755)
    print(f'Embedded {theme_count} catalog themes ({folder_count} HTML folders) and {asset_count} local files.')


if __name__ == '__main__':
    main()
