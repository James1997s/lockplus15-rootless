#!/usr/bin/env python3
"""Add full native lock-screen composition layers to every LockPlus catalog theme."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'themes'
CATALOG = ROOT / 'catalog.json'
PALETTES = [
    ('#071A2E', '#163A5F', '#2C7DA0'),
    ('#17102D', '#39235C', '#8B5CF6'),
    ('#0A2021', '#14532D', '#22C55E'),
    ('#2A0B1A', '#701A75', '#EC4899'),
    ('#21130A', '#7C2D12', '#F59E0B'),
    ('#07121F', '#1E3A8A', '#38BDF8'),
    ('#1B1020', '#5B214D', '#FB7185'),
    ('#0A1326', '#1E293B', '#94A3B8'),
]


def rgba(hex_color: str, alpha: float) -> str:
    value = hex_color.lstrip('#')
    red, green, blue = int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)
    return f'rgba({red},{green},{blue},{alpha:.2f})'


def panel(title: str, top: int, palette: tuple[str, str, str], small: bool = False) -> dict[str, str]:
    return {
        'type': 'panel',
        'position': 'absolute',
        'left': '50%',
        'top': f'{top}px',
        'transform': 'translateX(-50%)',
        'width': '314px',
        'height': '36px' if small else '64px',
        'padding': '0px',
        'background-color': rgba(palette[1], 0.66),
        'border': f'1px solid {rgba(palette[2], 0.72)}',
        'border-radius': '18px',
        'box-shadow': f'0 6px 20px {rgba(palette[0], 0.46)}',
        'innerHTML': title,
        'color': '#F8FAFC',
        'font-family': 'HelveticaNeue-Medium',
        'font-size': '10px' if small else '12px',
        'font-weight': '700',
        'letter-spacing': '2px' if small else '1px',
        'z-index': '4',
    }


def composition(name: str, index: int) -> dict[str, dict[str, str]]:
    palette = PALETTES[index % len(PALETTES)]
    return {
        'wallpaper': {
            'type': 'wallpaper',
            'position': 'absolute',
            'left': '50%',
            'top': '0px',
            'transform': 'translateX(-50%)',
            'gradient': '|'.join(palette),
            'z-index': '-100',
        },
        'themeBanner': panel(name.upper(), 214, palette),
        'themeFooter': panel('LOCKPLUS 15  •  GITHUB THEME', 488, palette, small=True),
    }


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding='utf-8'))
    for index, record in enumerate(catalog['themes']):
        path = ROOT / record['url']
        theme = json.loads(path.read_text(encoding='utf-8'))
        elements = theme.setdefault('placedElements', {})
        elements.update(composition(record['name'], index))
        path.write_text(json.dumps(theme, indent=2) + '\n', encoding='utf-8')
    print(f'Upgraded {len(catalog["themes"])} themes with full visual compositions.')


if __name__ == '__main__':
    main()
