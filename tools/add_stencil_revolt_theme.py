#!/usr/bin/env python3
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path('/home/ubuntu/lockplus15-rootless')
SOURCE = ROOT / 'previews' / 'stencil-revolt-theme'
TARGET = ROOT / 'themes' / 'folder-themes' / 'stencil-revolt'
CATALOG = ROOT / 'themes' / 'catalog.json'

TARGET.mkdir(parents=True, exist_ok=True)
shutil.copy2(SOURCE / 'index.html', TARGET / 'LockBackground.html')
for name in ('style.css', 'script.js', 'wallpaper.jpeg'):
    shutil.copy2(SOURCE / name, TARGET / name)

files = []
for path in ('LockBackground.html', 'script.js', 'style.css', 'wallpaper.jpeg'):
    data = (TARGET / path).read_bytes()
    files.append({'path': path, 'sha256': hashlib.sha256(data).hexdigest()})

manifest = {
    'id': 'stencil-revolt',
    'name': 'Comic Graffiti Wall Clock',
    'description': 'Monochrome comic-graffiti collage with a darkened wallpaper, one large Sour Gummy live clock, and a small live date; no notifications, notch, or status-bar overlay.',
    'format': 'folder',
    'entry': 'LockBackground.html',
    'basePath': 'folder-themes/stencil-revolt',
    'files': files,
}
(TARGET / 'stencil-revolt.json').write_text(json.dumps(manifest, indent=2) + '\n')

catalog = json.loads(CATALOG.read_text())
themes = catalog.setdefault('themes', [])
record = {'id': manifest['id'], 'name': manifest['name'], 'description': manifest['description'], 'format': 'folder', 'url': 'folder-themes/stencil-revolt/stencil-revolt.json'}
if not any(item.get('id') == manifest['id'] for item in themes):
    themes.append(record)
else:
    themes[:] = [record if item.get('id') == manifest['id'] else item for item in themes]
CATALOG.write_text(json.dumps(catalog, indent=2) + '\n')
print(json.dumps({'theme': manifest, 'catalog_count': len(themes)}, indent=2))
