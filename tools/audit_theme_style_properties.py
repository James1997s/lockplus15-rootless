#!/usr/bin/env python3
"""Report every declarative style property used by the local LockPlus catalog."""
from __future__ import annotations

import collections
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'themes'
catalog = json.loads((ROOT / 'catalog.json').read_text(encoding='utf-8'))
counts: collections.Counter[str] = collections.Counter()
for record in catalog['themes']:
    theme = json.loads((ROOT / record['url']).read_text(encoding='utf-8'))
    for properties in theme['placedElements'].values():
        counts.update(properties.keys())

for key, count in sorted(counts.items()):
    print(f'{count:3d}  {key}')
