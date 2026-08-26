#!/usr/bin/env python3
"""Copy user-supplied legacy web assets into the SpecialLock rootless Theos layout.

The public repository contains no legacy web assets or binaries. This tool
uses a local, user-supplied asset directory and only copies static HTML,
JavaScript, styles, images, fonts, and media. It never copies or executes
Mach-O binaries.
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
DESTINATION = PROJECT / 'layout/Library/SpecialLock'
BUNDLED_THEMES = PROJECT / 'themes'


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        'legacy_root',
        type=Path,
        help='Path containing the legacy LockPlus and Creator asset directories',
    )
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    legacy_root = arguments.legacy_root.expanduser().resolve()

    missing = [str(legacy_root / name) for name in ('LockPlus', 'Creator') if not (legacy_root / name).is_dir()]
    if missing:
        raise SystemExit('Missing legacy static asset directories:\n' + '\n'.join(missing))

    if DESTINATION.exists():
        shutil.rmtree(DESTINATION)
    DESTINATION.mkdir(parents=True)
    shutil.copytree(BUNDLED_THEMES, DESTINATION / 'Themes')

    for name in ('LockPlus', 'Creator'):
        shutil.copytree(legacy_root / name, DESTINATION / name, ignore=shutil.ignore_patterns('.DS_Store'))

    text_extensions = {'.html', '.js', '.css'}
    for path in DESTINATION.rglob('*'):
        if path.suffix.lower() not in text_extensions:
            continue
        content = path.read_text(encoding='utf-8', errors='surrogateescape')

        # Resource calls from the legacy renderer now use the bootstrap-provided
        # rootless data path. Existing local assets remain relative to the page.
        content = content.replace('file:///Library/LockPlus/Creator/images/blank.png', '../Creator/images/blank.png')
        if path.name in {'index.html', 'Wallpaper.html'} and path.parent.name == 'LockPlus':
            content = content.replace(
                'artworkPreload.src = "file:///var/mobile/Library/LockPlus/Artwork.jpg?" +',
                'artworkPreload.src = window.SpecialLock.artworkURL + "?" +',
            )
            content = content.replace(
                "'url(\"file:///var/mobile/Library/LockPlus/Artwork.jpg?' + new Date().getMilliseconds() + '\")'",
                "'url(\"' + window.SpecialLock.artworkURL + '?' + new Date().getMilliseconds() + '\")'",
            )
        content = content.replace('/Library/LockPlus/fonts/', '/var/jb/Library/SpecialLock/fonts/')

        if path.name == 'index.html' and path.parent.name == 'Creator':
            content = content.replace('file:///Library/LockPlus/LockPlus/index.html', '../LockPlus/index.html')
        elif 'extras' in path.parts:
            content = content.replace('file:///Library/LockPlus/LockPlus/index.html', '../../index.html')

        # The Creator's JavaScript runs with Creator/index.html as its document base.
        if 'Creator' in path.parts and path.name == 'action_addremove.js':
            content = content.replace('../Creator/images/blank.png', 'images/blank.png')

        path.write_text(content, encoding='utf-8', errors='surrogateescape')

    print(f'Migrated static assets to {DESTINATION}')


if __name__ == '__main__':
    main()
