#!/usr/bin/env python3
import hashlib
import json
import shutil
from pathlib import Path

repo = Path('/home/ubuntu/lockplus15-rootless')
source = repo / 'previews' / 'animated_lockscreen_source'
theme_id = 'animated-psychedelic-cat'
theme_dir = repo / 'themes' / 'folder-themes' / theme_id
theme_dir.mkdir(parents=True, exist_ok=True)

for source_name, target_name in [('index.html', 'LockBackground.html'), ('style.css', 'style.css'), ('script.js', 'script.js')]:
    shutil.copy2(source / source_name, theme_dir / target_name)

files = []
for name in ('LockBackground.html', 'style.css', 'script.js'):
    data = (theme_dir / name).read_bytes()
    files.append({'path': name, 'sha256': hashlib.sha256(data).hexdigest()})
manifest = {
    'id': theme_id,
    'name': 'Animated Psychedelic Cat',
    'description': 'Animated geometric cat lock screen with live date and time; no notification, notch, or status-bar markup.',
    'format': 'folder',
    'entry': 'LockBackground.html',
    'basePath': f'folder-themes/{theme_id}',
    'files': files,
}
(theme_dir / f'{theme_id}.json').write_text(json.dumps(manifest, indent=2) + '\n')

catalog_path = repo / 'themes' / 'catalog.json'
catalog = json.loads(catalog_path.read_text())
records = [x for x in catalog['themes'] if x.get('id') != theme_id]
records.append({
    'id': theme_id,
    'name': 'Animated Psychedelic Cat',
    'description': manifest['description'],
    'format': 'folder',
    'url': f'folder-themes/{theme_id}/{theme_id}.json',
})
catalog['themes'] = records
catalog_path.write_text(json.dumps(catalog, indent=2) + '\n')
print(json.dumps({'theme': theme_id, 'catalog_count': len(records), 'files': files}))
