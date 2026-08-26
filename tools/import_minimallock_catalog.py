#!/usr/bin/env python3
"""Generate safe declarative LockPlus themes from a MinimalLock bundle index.

The converter uses only the display-name and slug fields from Tweak-Index.tsv.
It does not copy, compile, execute, or publish source code, binaries, images,
or other assets from the source bundle.
"""
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
BASE_THEMES = PROJECT / 'themes'
OUTPUT_DIRECTORY = BASE_THEMES / 'minimallock'
CATALOG_PATH = BASE_THEMES / 'catalog.json'

ACCENTS = {
    'bee-notepad': '#F6C945', 'mac-desk-clock': '#F7F7F2',
    'binary-matrix-clock': '#00FF70', 'blueprint-grid-clock': '#1EA7FD',
    'bubblegum-orb-clock': '#FF85C8', 'dot-matrix-clock': '#FF714B',
    'flip-panel-clock': '#E2E8F0', 'freshlock': '#55E6B6',
    'graffiti-marker-clock': '#F43F5E', 'station-watch-clock': '#FFD166',
    'ios-26-big-text-clock': '#F5F5F7', 'lava-lamp-clock': '#FF5A36',
    'liquid-wave-clock': '#43D9FF', 'surreal-melt-clock': '#FE62A7',
    'mouse-hands-clock': '#F6D365', 'neon-arcade-clock': '#00F0FF',
    'neon-halo-clock': '#B26DFF', 'penguin-walk-clock': '#80D8FF',
    'prism-light-clock': '#A3FF12', 'radial-progress-clock': '#FFC857',
    'retro-led-clock': '#FF512F', 'split-flap-terminal-clock': '#44FF99',
    'starfield-night-watch': '#B9C6FF', 'steamboat-wave-clock': '#71E5FF',
    'sunset-horizon-clock': '#FF9E5C', 'tamagotchi-pixel-clock': '#B5FF4B',
    'terminal-green-clock': '#00FF66', 'typewriter-desk-clock': '#E5D1B8',
    'vaporwave-dream-clock': '#FF55DD', 'weather-panel': '#60C4FF',
    'editorial-word-clock': '#EAEAEA', 'mooner': '#E5E7EB',
}


def fallback_accent(slug: str) -> str:
    digest = hashlib.sha256(slug.encode('utf-8')).hexdigest()
    return '#' + digest[:6].upper()


def theme_payload(display_name: str, slug: str) -> dict:
    accent = ACCENTS.get(slug, fallback_accent(slug))
    label = display_name.upper()
    return {
        'placedElements': {
            'clock': {
                'type': 'clock', 'position': 'absolute', 'left': '50%', 'top': '72px',
                'transform': 'translateX(-50%)', 'color': accent,
                'font-family': 'HelveticaNeue-UltraLight', 'font-size': '62px',
                'font-weight': '200', 'letter-spacing': '-1px',
                'text-shadow': f'0 0 15px {accent}99', 'z-index': '20',
            },
            'todaystrings': {
                'type': 'date', 'position': 'absolute', 'left': '50%', 'top': '142px',
                'transform': 'translateX(-50%)', 'color': 'rgba(255,255,255,0.92)',
                'font-family': 'HelveticaNeue-Medium', 'font-size': '16px',
                'font-weight': '500', 'letter-spacing': '0.4px', 'z-index': '20',
            },
            'themeLabel': {
                'type': 'text', 'position': 'absolute', 'left': '50%', 'top': '184px',
                'transform': 'translateX(-50%)', 'innerHTML': label, 'color': accent,
                'font-family': 'HelveticaNeue-Bold', 'font-size': '10px',
                'font-weight': '700', 'letter-spacing': '3px', 'z-index': '20',
            },
        }
    }


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('index', type=Path, help='Path to MinimalLock Tweak-Index.tsv')
    arguments = parser.parse_args()

    rows: list[tuple[str, str]] = []
    with arguments.index.open(encoding='utf-8', newline='') as handle:
        for row in csv.reader(handle, delimiter='\t'):
            if len(row) < 6 or row[0] in {'Display Name', 'Tweak Name'}:
                continue
            display_name, slug = row[0].strip(), row[5].strip()
            if display_name and slug:
                rows.append((display_name, slug))

    if OUTPUT_DIRECTORY.exists():
        for stale_file in OUTPUT_DIRECTORY.glob('*.json'):
            stale_file.unlink()
    OUTPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    for display_name, slug in rows:
        path = OUTPUT_DIRECTORY / f'{slug}.json'
        path.write_text(json.dumps(theme_payload(display_name, slug), indent=2) + '\n', encoding='utf-8')

    catalog = json.loads(CATALOG_PATH.read_text(encoding='utf-8'))
    catalog['themes'] = [
        item for item in catalog.get('themes', [])
        if isinstance(item, dict) and not str(item.get('id', '')).startswith('minimallock-')
    ]
    generated_records = [
        {'id': f'minimallock-{slug}', 'name': display_name, 'url': f'minimallock/{slug}.json'}
        for display_name, slug in rows
    ]
    catalog['themes'].extend(generated_records)
    catalog['catalogName'] = 'LockPlus 15 Theme Catalog'
    CATALOG_PATH.write_text(json.dumps(catalog, indent=2) + '\n', encoding='utf-8')
    print(f'Generated {len(rows)} themes in {OUTPUT_DIRECTORY}')


if __name__ == '__main__':
    main()
